# Read a .packages manifest the way install/wsl/packages.sh needs it: comments
# and whitespace stripped, blank lines dropped, sorted so two lists can be
# combined with comm(1).
read_package_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | sort -u
}
