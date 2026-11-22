#!/bin/sh
# Checks that everything PAVÉ needs is installed; says how to install what is missing.
#   tools/check_deps.sh            check only (exit status 1 if something required is missing)
#   tools/check_deps.sh --install  install the missing packages (Debian / Ubuntu / Mint: apt)
cd "$(dirname "$0")/.." || exit 1

missing_req=""     # apt packages that are required
missing_opt=""     # apt packages that are recommended
problems=0

ok()   { printf '  \033[32mok\033[0m       %s\n' "$1"; }
miss() { printf '  \033[31mmissing\033[0m  %s\n' "$1"; problems=$((problems + 1)); missing_req="$missing_req $2"; }
opt()  { printf '  \033[33moptional\033[0m %s\n' "$1"; missing_opt="$missing_opt $2"; }

# the GtkAda development package has the library version in its name (libgtkada20-dev, ...)
gtkada_pkg() {
  if command -v apt-cache >/dev/null 2>&1; then
    apt-cache search --names-only '^libgtkada[0-9.]*-dev$' 2>/dev/null | sort -V | tail -1 | cut -d' ' -f1
  fi
}

echo "Checking what PAVÉ needs:"

# compiler and build tool
if command -v gnatmake >/dev/null 2>&1 || command -v gnat >/dev/null 2>&1; then
  ok "GNAT Ada compiler"
else
  miss "GNAT Ada compiler" "gnat"
fi
if command -v gprbuild >/dev/null 2>&1; then
  ok "gprbuild"
else
  miss "gprbuild" "gprbuild"
fi

# GtkAda: try to load a project that depends on it
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'with "gtkada";\nproject T is\n   for Source_Dirs use ();\nend T;\n' > "$tmp/t.gpr"
if command -v gprbuild >/dev/null 2>&1 && gprbuild -q -P "$tmp/t.gpr" >/dev/null 2>&1; then
  ok "GtkAda (GTK 3 for Ada)"
else
  miss "GtkAda (GTK 3 for Ada)" "$(gtkada_pkg)"
fi

# PulseAudio client library: try to link against it
printf 'int main(void){return 0;}\n' > "$tmp/t.c"
if command -v gcc >/dev/null 2>&1 && gcc "$tmp/t.c" -o "$tmp/t" -lpulse-simple -lpulse >/dev/null 2>&1; then
  ok "PulseAudio client library (sound)"
else
  miss "PulseAudio client library (sound)" "libpulse-dev"
fi

# Python: needed to download and build the maps
if command -v python3 >/dev/null 2>&1; then
  ok "Python 3 (map download)"
  if python3 -c "import osmium" >/dev/null 2>&1; then
    ok "pyosmium (fast, reliable map downloads from Geofabrik)"
  else
    opt "pyosmium - recommended: needed for All of Paris and Copenhagen when the Overpass servers are busy" "python3-pyosmium"
  fi
else
  miss "Python 3 (map download)" "python3"
fi

# only for tools/make_media.sh
if command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg (only for 'make media')"
else
  opt "ffmpeg - only for 'make media' (README screenshots and GIFs)" "ffmpeg"
fi

pkgs=$(echo "$missing_req $missing_opt" | xargs)
if [ "$1" = "--install" ]; then
  if [ -z "$pkgs" ]; then
    echo "Nothing to install."
    exit 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing: $pkgs"
    sudo apt-get install -y $pkgs
    exit $?
  fi
  echo "This system has no apt-get. Please install the packages above with your package manager"
  echo "(e.g. Fedora: gcc-gnat gprbuild gtkada-devel pulseaudio-libs-devel python3-osmium)."
  exit 1
fi

if [ "$problems" -gt 0 ]; then
  echo
  echo "Something required is missing. Install it with:  make deps"
  [ -n "$pkgs" ] && command -v apt-get >/dev/null 2>&1 && echo "  (which runs: sudo apt-get install $pkgs)"
  exit 1
fi
if [ -n "$missing_opt" ]; then
  echo
  echo "Everything required is there. Recommended extras:  make deps  (sudo apt-get install$(echo "$missing_opt" | sed 's/^/ /;s/  */ /g'))"
fi
exit 0
