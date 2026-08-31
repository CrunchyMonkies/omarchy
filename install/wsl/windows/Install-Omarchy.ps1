<#
.SYNOPSIS
  Installs Omarchy as a WSL distribution on Windows.

.DESCRIPTION
  Installs the VKMS kernel the desktop needs, imports an Omarchy .wsl image, and
  unpacks the kernel modules.

  Both the image and the kernel are fetched from a release and verified against
  its SHA256SUMS, unless you point at your own with -ImagePath or -KernelPath.

  The image is a bootstrap: it carries Omarchy's first-run setup screen, and the
  first launch asks a few questions and then downloads and installs the rest.
  That needs a network connection and takes a while.

  This is the one part of the WSL setup that cannot live inside the image: it
  runs on Windows, before any Omarchy distribution exists. See README.wsl.md for
  the manual equivalent of every step, and docs/wsl.md for why each is needed.

  Nothing here needs administrator rights, and none are requested.

.PARAMETER Tag
  The release to take the image and kernel from, for example 202608.31.0.
  Defaults to the latest.

.PARAMETER Name
  The name to register the distribution under. Defaults to Omarchy.

.PARAMETER Location
  Where to store the distribution. Defaults to %USERPROFILE%\WSL\Omarchy.

.PARAMETER ImagePath
  Import a locally built .wsl image, as produced by 'omarchy dev wsl build',
  instead of fetching the release's.

.PARAMETER KernelPath
  Install a locally built bzImage instead of fetching the release's. Its modules
  are taken from <KernelPath>-modules.tar.gz, which is where the build writes
  them.

.PARAMETER SkipKernel
  Import the image without touching the kernel or .wslconfig. The CLI works;
  'start-omarchy' does not, because a stock WSL2 kernel exposes no DRM device.

.PARAMETER Force
  Replace an existing distribution of the same name, and overwrite an existing
  kernel= line in .wslconfig.

.EXAMPLE
  .\Install-Omarchy.ps1

.EXAMPLE
  .\Install-Omarchy.ps1 -ImagePath ~\omarchy.wsl -KernelPath ~\bzImage

.EXAMPLE
  .\Install-Omarchy.ps1 -Name Omarchy-test -Force
#>

[CmdletBinding()]
param(
  [string] $Tag = 'latest',
  [string] $Name = 'Omarchy',
  [string] $Location = "$env:USERPROFILE\WSL\Omarchy",
  [string] $ImagePath,
  [string] $KernelPath,
  [switch] $SkipKernel,
  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = 'CrunchyMonkies/omarchy'

# The five modules docs/wsl.md names. Nothing autoloads modules under WSL2 --
# the kernel runs /sbin/modprobe in the utility VM's root, where neither it nor
# /lib/modules exists -- so every module has to be named up front. Without these
# dockerd fails with "Extension addrtype revision 0 not supported".
$RequiredModules = @('bridge', 'nft_compat', 'xt_addrtype', 'xt_MASQUERADE', 'xt_conntrack')

# wsl.exe writes UTF-16LE unless told otherwise, which PowerShell reads back as
# text with a NUL between every character.
$env:WSL_UTF8 = '1'

# ------------------------------------------------------------------- output

function Write-Step {
  param([string] $Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Green
}

function Write-Note {
  param([string] $Message)
  Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Warn {
  param([string] $Message)
  Write-Host "    ! $Message" -ForegroundColor Yellow
}

function Invoke-Native {
  param(
    [string] $File,
    [string[]] $Arguments
  )

  # $ErrorActionPreference = 'Stop' turns a native command's stderr into a
  # terminating error the moment 2>&1 merges it into the success stream, so
  # anything whose output we want to read has to relax it first.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'

  try {
    $output = & $File @Arguments 2>&1
  } finally {
    $ErrorActionPreference = $previous
  }

  return @{
    Output   = @($output | ForEach-Object { "$_" })
    ExitCode = $LASTEXITCODE
  }
}

function Stop-WithError {
  param([string] $Message)
  Write-Host ''
  Write-Host "Error: $Message" -ForegroundColor Red
  exit 1
}

# ----------------------------------------------------------------- preflight

function Assert-Prerequisites {
  Write-Step 'Checking this machine'

  if ($PSVersionTable.PSVersion.Major -lt 5) {
    Stop-WithError 'PowerShell 5.1 or newer is required.'
  }

  # 'wsl --version' exists only in the Store build of WSL, which is also the
  # only one that ships WSLg. The inbox Windows 10 build answers with an error,
  # which is exactly the case that has to be turned away.
  $wsl = Invoke-Native -File 'wsl.exe' -Arguments @('--version')

  if ($wsl.ExitCode -ne 0) {
    Stop-WithError @'
WSL 2 with WSLg is required, and this looks like an older WSL.

Install or update it with:
  wsl --install
  wsl --update
'@
  }

  Write-Note ($wsl.Output | Select-Object -First 1)

  if (-not ($wsl.Output -match 'WSLg')) {
    Write-Warn 'This WSL does not report a WSLg version. The desktop needs WSLg.'
  }

  # The image unpacks to several times the size of the download, and it is not
  # obvious in advance which drive that lands on.
  $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Location))
  $drive = Get-PSDrive -Name $root.Substring(0, 1) -ErrorAction SilentlyContinue

  if ($drive -and $drive.Free) {
    $free = [math]::Round($drive.Free / 1GB, 1)
    Write-Note "$free GB free on $root"

    if ($drive.Free -lt 25GB) {
      Write-Warn 'Less than 25 GB free. The image needs room to unpack as well as to download.'
    }
  }
}

# ------------------------------------------------------------------ download

$script:ReleaseCache = @{}

function Get-Release {
  param([string] $Tag)

  # Both the image and the kernel come from the same release, and each asks for
  # it. GitHub rate-limits unauthenticated API calls tightly enough to care.
  if ($script:ReleaseCache.ContainsKey($Tag)) {
    return $script:ReleaseCache[$Tag]
  }

  if ($Tag -eq 'latest') {
    $url = "https://api.github.com/repos/$Repo/releases/latest"
  } else {
    $url = "https://api.github.com/repos/$Repo/releases/tags/$Tag"
  }

  # PowerShell 5.1 still defaults to TLS 1.0, which api.github.com refuses.
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  try {
    $release = Invoke-RestMethod -Uri $url -Headers @{
      'Accept'     = 'application/vnd.github+json'
      'User-Agent' = 'Install-Omarchy'
    }

    Write-Step "Resolving the $Tag release"
    Write-Note "$($release.tag_name), published $($release.published_at)"

    $script:ReleaseCache[$Tag] = $release
    return $release
  } catch {
    Stop-WithError "Could not read the release from $url`n$($_.Exception.Message)"
  }
}

function Save-Asset {
  param(
    [object] $Asset,
    [string] $Directory
  )

  $path = Join-Path $Directory $Asset.name
  $size = [math]::Round($Asset.size / 1MB, 1)

  # The image and the kernel are verified against the same SHA256SUMS, and the
  # second caller has no reason to fetch it again.
  if (Test-Path $path) {
    return $path
  }

  Write-Note "$($Asset.name) ($size MB)"

  # Invoke-WebRequest's progress bar costs more than the download itself on
  # PowerShell 5.1, by a wide margin, on a file this size.
  $previous = $ProgressPreference
  $ProgressPreference = 'SilentlyContinue'

  try {
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $path -UseBasicParsing
  } finally {
    $ProgressPreference = $previous
  }

  return $path
}

function Assert-Checksum {
  param(
    [string] $Path,
    [hashtable] $Sums
  )

  $name = Split-Path $Path -Leaf

  if (-not $Sums.ContainsKey($name)) {
    Write-Warn "$name is not listed in SHA256SUMS; cannot verify it."
    return
  }

  $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()

  if ($actual -ne $Sums[$name]) {
    Stop-WithError @"
$name failed its checksum. Nothing has been installed.

  expected $($Sums[$name])
  got      $actual

Delete it and run this again.
"@
  }

  Write-Note "$name verified"
}

function Read-Sha256Sums {
  param([string] $Path)

  $sums = @{}

  foreach ($line in Get-Content -Path $Path) {
    # sha256sum writes "<hash>  <name>", two spaces, no quoting.
    if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
      $sums[$Matches[2].Trim()] = $Matches[1].ToLower()
    }
  }

  return $sums
}

function Get-ReleaseImage {
  param(
    [string] $Tag,
    [string] $Directory
  )

  $release = Get-Release -Tag $Tag

  $assets = @{}
  foreach ($asset in $release.assets) { $assets[$asset.name] = $asset }

  # The image is named for the tag, and a manual -Tag may not be the tag the
  # release ended up with, so match on the shape rather than composing a name.
  $image = $assets.Values | Where-Object { $_.name -like 'omarchy-*.wsl' } | Select-Object -First 1

  if (-not $image) {
    Stop-WithError "The $($release.tag_name) release carries no .wsl image. Build one with 'omarchy dev wsl build' and pass -ImagePath."
  }

  if (-not $assets.ContainsKey('SHA256SUMS')) {
    Stop-WithError "The $($release.tag_name) release carries no SHA256SUMS, so nothing can be verified."
  }

  Write-Step 'Downloading the image'
  Write-Note 'A gigabyte or two. The rest of Omarchy is downloaded by the first launch, not here.'

  $sumsPath = Save-Asset -Asset $assets['SHA256SUMS'] -Directory $Directory
  $sums = Read-Sha256Sums -Path $sumsPath

  $path = Save-Asset -Asset $image -Directory $Directory
  Assert-Checksum -Path $path -Sums $sums

  return $path
}

function Get-ReleaseKernel {
  param(
    [string] $Tag,
    [string] $Directory
  )

  $release = Get-Release -Tag $Tag

  $assets = @{}
  foreach ($asset in $release.assets) { $assets[$asset.name] = $asset }

  if (-not ($assets.ContainsKey('bzImage') -and $assets.ContainsKey('bzImage-modules.tar.gz'))) {
    Write-Warn "$($release.tag_name) carries no kernel yet; it is built separately and can lag the release."
    return $null
  }

  if (-not $assets.ContainsKey('SHA256SUMS')) {
    Stop-WithError "The $($release.tag_name) release carries no SHA256SUMS, so nothing can be verified."
  }

  Write-Step 'Downloading the kernel'

  $sumsPath = Save-Asset -Asset $assets['SHA256SUMS'] -Directory $Directory
  $sums = Read-Sha256Sums -Path $sumsPath

  $kernel = Save-Asset -Asset $assets['bzImage'] -Directory $Directory
  Assert-Checksum -Path $kernel -Sums $sums

  $modules = Save-Asset -Asset $assets['bzImage-modules.tar.gz'] -Directory $Directory
  Assert-Checksum -Path $modules -Sums $sums

  return @{
    Kernel  = $kernel
    Modules = $modules
  }
}

# -------------------------------------------------------------------- kernel

function Update-WslConfig {
  param([string] $KernelPath)

  $config = Join-Path $env:USERPROFILE '.wslconfig'

  # .wslconfig reads kernel= as an escaped string, so every backslash has to be
  # doubled. A single-backslash path does not resolve and WSL quietly boots its
  # own kernel instead -- which looks exactly like a kernel that built wrong.
  $escaped = $KernelPath -replace '\\', '\\'

  $lines = @()
  if (Test-Path $config) {
    $backup = "$config.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $config -Destination $backup
    Write-Note "Backed up .wslconfig to $(Split-Path $backup -Leaf)"

    $lines = @(Get-Content -Path $config)

    $existing = $lines | Where-Object { $_ -match '^\s*kernel\s*=' }
    if ($existing -and -not $Force) {
      Stop-WithError @"
.wslconfig already sets a kernel:

  $existing

Pass -Force to replace it, or edit $config by hand.
"@
    }
  }

  $output = New-Object System.Collections.ArrayList
  $inWsl2 = $false
  $written = $false

  foreach ($line in $lines) {
    if ($line -match '^\s*\[') {
      # Leaving [wsl2] without having replaced anything means the section had no
      # kernel= to replace, so add one before moving on.
      if ($inWsl2 -and -not $written) {
        [void] $output.Add("kernel=$escaped")
        $written = $true
      }
      $inWsl2 = $line -match '^\s*\[wsl2\]\s*$'
    }

    if ($inWsl2 -and $line -match '^\s*kernel\s*=') {
      [void] $output.Add("kernel=$escaped")
      $written = $true
    } else {
      [void] $output.Add($line)
    }
  }

  if ($inWsl2 -and -not $written) {
    [void] $output.Add("kernel=$escaped")
    $written = $true
  }

  if (-not $written) {
    if ($output.Count -gt 0) { [void] $output.Add('') }
    [void] $output.Add('[wsl2]')
    [void] $output.Add("kernel=$escaped")
  }

  # Not Set-Content -Encoding UTF8: on PowerShell 5.1 that writes a BOM, and
  # .wslconfig is parsed as a plain INI file.
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($config, [string[]] $output, $utf8)
  Write-Note "kernel=$escaped"
}

function Install-Kernel {
  param(
    [string] $KernelPath,
    [string] $ModulesPath
  )

  Write-Step 'Installing the kernel'

  $destination = Join-Path $env:USERPROFILE 'bzImage'
  Copy-Item -Path $KernelPath -Destination $destination -Force
  Write-Note "Copied to $destination"

  if ($ModulesPath) {
    Copy-Item -Path $ModulesPath -Destination (Join-Path $env:USERPROFILE 'bzImage-modules.tar.gz') -Force
  }

  Update-WslConfig -KernelPath $destination

  Write-Warn 'kernel= is global: every WSL distribution on this machine now boots this kernel.'
  Write-Warn 'Unpack the modules into the others too, or they will lose every module-built feature.'

  Write-Step 'Restarting WSL so the kernel takes effect'
  & wsl.exe --shutdown
}

# --------------------------------------------------------------------- image

function Get-Distributions {
  $output = & wsl.exe --list --quiet 2>$null

  if ($LASTEXITCODE -ne 0) { return @() }

  return @($output | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Import-Image {
  param(
    [string] $Path,
    [string] $Name,
    [string] $Location
  )

  Write-Step "Importing $Name"

  if ((Get-Distributions) -contains $Name) {
    if (-not $Force) {
      Stop-WithError @"
A distribution named '$Name' already exists.

Pass -Force to replace it -- which permanently deletes everything in it -- or
pass -Name to install alongside it.
"@
    }

    Write-Warn "Unregistering the existing '$Name'. Everything in it is deleted."
    & wsl.exe --unregister $Name

    if ($LASTEXITCODE -ne 0) {
      Stop-WithError "Could not unregister '$Name'."
    }
  }

  New-Item -ItemType Directory -Path $Location -Force | Out-Null

  & wsl.exe --install --from-file $Path --location $Location --name $Name

  if ($LASTEXITCODE -ne 0) {
    Stop-WithError "Importing the image failed. The image is still at $Path."
  }
}

# ------------------------------------------------------------------- modules

function Install-Modules {
  param(
    [string] $ModulesPath,
    [string] $Distribution
  )

  # The kernel this installs is a bzImage alone, and the stock WSL kernel keeps
  # most of itself as modules. Without unpacking them every =m option silently
  # disappears; dockerd is the first thing to notice.
  $resolved = Invoke-Native -File 'wsl.exe' -Arguments @('-d', $Distribution, '-u', 'root', '--', 'wslpath', '-a', $ModulesPath)

  if ($resolved.ExitCode -ne 0) {
    Write-Warn "Could not reach $Distribution to unpack the modules."
    Write-Warn 'Launch it once to finish first-run setup, then run this again.'
    return
  }

  $wslPath = $resolved.Output | Select-Object -First 1

  & wsl.exe -d $Distribution -u root -- tar -C / -xzf $wslPath

  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Unpacking the modules into $Distribution failed."
    return
  }

  $modules = $RequiredModules -join ' '
  & wsl.exe -d $Distribution -u root -- bash -c "printf '%s\n' $modules > /etc/modules-load.d/wsl-kernel.conf"

  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Could not write /etc/modules-load.d/wsl-kernel.conf in $Distribution."
    return
  }

  Write-Note "$Distribution : modules unpacked and recorded"
}

# ---------------------------------------------------------------------- main

Write-Host ''
Write-Host 'Omarchy for WSL' -ForegroundColor Cyan

if ($ImagePath -and -not (Test-Path $ImagePath)) {
  Stop-WithError "No such image: $ImagePath"
}

Assert-Prerequisites

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) "omarchy-install-$PID"
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

try {
  if ($ImagePath) {
    # Taken on trust: there is nothing published to check a local build
    # against, and you built it.
    Write-Step 'Using the image you built'

    $image = (Resolve-Path -Path $ImagePath).Path
    Write-Note $image
  } else {
    $image = Get-ReleaseImage -Tag $Tag -Directory $workspace
  }

  $kernel = $null
  $modules = $null

  if ($KernelPath) {
    $kernel = (Resolve-Path -Path $KernelPath).Path
    Write-Note $kernel

    # 'omarchy dev wsl kernel' writes the modules next to the bzImage under
    # this exact name.
    $candidate = "$kernel-modules.tar.gz"

    if (Test-Path $candidate) {
      $modules = $candidate
      Write-Note $modules
    } else {
      Write-Warn "No $candidate beside the kernel; modules will not be installed."
    }
  } elseif (-not $SkipKernel) {
    # The kernel is small enough to publish and takes hours to build, so it is
    # the one piece worth fetching.
    $fetched = Get-ReleaseKernel -Tag $Tag -Directory $workspace

    if ($fetched) {
      $kernel = $fetched.Kernel
      $modules = $fetched.Modules
    }
  }

  $kernelInstalled = $false

  if ($SkipKernel) {
    Write-Step 'Skipping the kernel (-SkipKernel)'
    Write-Warn "The CLI will work. 'start-omarchy' will not: a stock WSL2 kernel has no DRM device."
  } elseif (-not $kernel) {
    Write-Step 'No kernel available'
    Write-Warn 'Nothing to install, so the desktop cannot start.'
    Write-Warn "The CLI works. Build one with 'omarchy dev wsl kernel' and pass -KernelPath."
  } else {
    Install-Kernel -KernelPath $kernel -ModulesPath $modules
    $kernelInstalled = $true
  }

  Import-Image -Path $image -Name $Name -Location $Location

  if ($kernelInstalled -and $modules) {
    Write-Step 'Unpacking the kernel modules'

    $windowsModules = Join-Path $env:USERPROFILE 'bzImage-modules.tar.gz'
    Install-Modules -ModulesPath $windowsModules -Distribution $Name

    # kernel= is global, so every other distribution is now booting a kernel
    # whose modules it does not have. Offer, rather than assume.
    $others = @(Get-Distributions | Where-Object { $_ -ne $Name })

    if ($others.Count -gt 0) {
      Write-Host ''
      Write-Host "    These distributions are now booting the new kernel too: $($others -join ', ')"
      $answer = Read-Host '    Unpack the modules into them as well? [y/N]'

      if ($answer -match '^[Yy]') {
        foreach ($other in $others) {
          Install-Modules -ModulesPath $windowsModules -Distribution $other
        }
      } else {
        Write-Warn 'Skipped. Unpack them by hand with: sudo tar -C / -xzf <bzImage-modules.tar.gz>'
      }
    }
  }
} finally {
  Remove-Item -Path $workspace -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Installed'

Write-Host @"

Two steps are left, both inside the distribution:

  wsl -d $Name
  omarchy setup wsl viewer   # fetches the Windows VNC client and makes a shortcut
  start-omarchy              # brings up the desktop

'omarchy setup wsl viewer' is what puts an Omarchy Desktop shortcut on your Windows
desktop and installs TurboVNC, which is the only viewer that grabs the keyboard in a
window -- without a grab, Windows keeps SUPER and no keybinding reaches the session.

If the desktop does not come up, run:

  start-omarchy --diagnose

It reports what the session needs against what this machine has, without starting
anything, and names the fix for whichever piece is missing.
"@
