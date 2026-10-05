#!/bin/sh
# Links the CaddieTools Spoons into Hammerspoon's Spoons directory, so
#   hs.loadSpoon("CaddieTools").use({ "TileManager", "EdgeSnap" })
# works from any config. Links rather than copies, so a pull updates them.
#
#   ./install.sh                 link every Spoon
#   ./install.sh EdgeSnap ...    link only these, plus CaddieCore and CaddieTools
#   ./install.sh --uninstall     remove the links this checkout made
#
# The target is ~/.hammerspoon/Spoons, or $HAMMERSPOON_SPOONS when set. Anything
# already there under the same name that is not a link to this checkout is left
# alone and reported.

set -eu

repo=$(cd "$(dirname "$0")" && pwd -P)
source_dir="$repo/Spoons"
target=${HAMMERSPOON_SPOONS:-"$HOME/.hammerspoon/Spoons"}

uninstall=false
if [ "${1:-}" = "--uninstall" ]; then
  uninstall=true
  shift
fi

if $uninstall; then
  [ -d "$target" ] || exit 0
  for link in "$target"/*.spoon; do
    [ -L "$link" ] || continue
    case $(readlink "$link") in
      "$source_dir"/*) rm "$link" && echo "removed $(basename "$link")" ;;
    esac
  done
  exit 0
fi

if [ "$#" -eq 0 ]; then
  names=""
  for dir in "$source_dir"/*.spoon; do names="$names $(basename "$dir" .spoon)"; done
else
  # Every Spoon needs CaddieCore, and use() needs CaddieTools
  names="CaddieCore CaddieTools $*"
fi

mkdir -p "$target"
status=0
for name in $names; do
  src="$source_dir/$name.spoon"
  dest="$target/$name.spoon"
  if [ ! -d "$src" ]; then
    echo "no Spoon named $name" >&2
    status=1
  elif [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "already linked $name"
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "skipped $name: $dest already exists and is not this checkout's" >&2
    status=1
  else
    ln -s "$src" "$dest"
    echo "linked $name"
  fi
done

cat <<EOF

Add to ~/.hammerspoon/init.lua, listing the Spoons you want:
  hs.loadSpoon("CaddieTools").use({ "TileManager", "TitleBarTweaks", "EdgeSnap", "MouseTweaks" })
EOF
exit $status
