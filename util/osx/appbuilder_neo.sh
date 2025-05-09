#!/bin/bash

echo "STEP 1 - PREPARE BUNDLE FOLDERS"

# Path setup
buildpath=${1:-"artifacts"}
basedir=${2:-"am"}
attractname="$basedir/attractplus"

bundlehome="$buildpath/Attract Mode Plus.app"
bundlecontent="$bundlehome/Contents"
bundlelibs="$bundlecontent/libs"

rm -Rf "$bundlehome"
mkdir -p "$bundlelibs" "$bundlecontent/MacOS" "$bundlecontent/Resources" "$bundlecontent/share/attract"

# Arrays to track libs
declare -a unresolved_paths
declare -a resolved_paths

# Set of visited/resolved libs to avoid duplicates
declare -A seen

function resolve_path() {
  local lib="$1"

  if [[ "$lib" == @rpath/* ]]; then
    local libname="${lib##*/}"
    local pkg_name="${libname%%.*}" # strip version if any
    local pkg_lib
    pkg_lib=$(pkg-config --libs-only-L "$pkg_name" 2>/dev/null)
    if [[ "$pkg_lib" == -L* ]]; then
      local libdir="${pkg_lib:2}" # strip '-L'
      echo "$libdir/$libname"
    elif [[ "$libname" == libsfml* ]]; then
      echo "am/obj/sfml/install/lib/$libname"
    fi
  elif [[ "$lib" == /opt/homebrew/* ]]; then
    echo "$lib"
  fi
}

function process_binary() {
  local bin="$1"
  local linked_libs
  linked_libs=$(otool -L "$bin" | awk 'NR>1 {print $1}')

  while IFS= read -r lib; do
    if [[ "$lib" == @rpath/* || "$lib" == /opt/homebrew/* ]]; then
      local resolved
      resolved=$(resolve_path "$lib")
      if [[ -n "$resolved" && -f "$resolved" && -z "${seen[$resolved]}" ]]; then
        unresolved_paths+=("$lib")
        resolved_paths+=("$resolved")
        seen[$resolved]=1
        process_binary "$resolved" # recurse
      fi
    fi
  done <<< "$linked_libs"
}

echo "STEP 2 - RESOLVE LIBRARY DEPENDENCIES"
process_binary "$attractname"

echo "STEP 3 - COPY LIBRARIES TO BUNDLE AND SET ID"
copied_libs=()

for ((i=0; i<${#resolved_paths[@]}; i++)); do
  resolved="${resolved_paths[$i]}"
  target="$bundlelibs/$(basename "$resolved")"
  cp "$resolved" "$target"
  chmod +w "$target"
  install_name_tool -id "@executable_path/../libs/$(basename "$target")" "$target"
  copied_libs+=("$resolved")
done

echo "STEP 4 - REWRITE LINKED PATHS IN COPIED LIBS"
for lib in "$bundlelibs"/*.dylib; do
  linked_libs=$(otool -L "$lib" | awk 'NR>1 {print $1}')
  for ((i=0; i<${#unresolved_paths[@]}; i++)); do
    from="${unresolved_paths[$i]}"
    to="@executable_path/../libs/$(basename "${resolved_paths[$i]}")"
    if echo "$linked_libs" | grep -q "$from"; then
      install_name_tool -change "$from" "$to" "$lib"
    fi
  done
done

echo "STEP 5 - REWRITE LINKED PATHS IN EXECUTABLE"
for ((i=0; i<${#unresolved_paths[@]}; i++)); do
  from="${unresolved_paths[$i]}"
  to="@executable_path/../libs/$(basename "${resolved_paths[$i]}")"
  if otool -L "$attractname" | grep -q "$from"; then
    install_name_tool -change "$from" "$to" "$attractname"
  fi
done

echo "✅ DONE"
