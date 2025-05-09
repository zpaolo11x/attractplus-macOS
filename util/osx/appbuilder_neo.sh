#!/bin/bash

set -euo pipefail

# STEP 1 - PREPARE BUNDLE FOLDERS
echo "STEP 1 - PREPARE BUNDLE FOLDERS"

buildpath=${1:-"artifacts"}
echo "Build Path: $buildpath"

bundlehome="$buildpath/Attract Mode Plus.app"
bundlecontent="$bundlehome/Contents"
bundlelibs="$bundlecontent/libs"

rm -Rf "$bundlehome"
mkdir -p "$bundlelibs" "$bundlecontent/MacOS" "$bundlecontent/Resources" "$bundlecontent/share/attract"

# STEP 2 - EXECUTABLE AND LIBRARY HANDLING
echo "STEP 2 - EXECUTABLE AND LIBRARY HANDLING"

basedir=${2:-"am"}
attractname="$basedir/attractplus"

if [ ! -f "$attractname" ]; then
  echo "Error: Executable $attractname does not exist!"
  exit 1
fi

VISITED=()
RESOLVED=()
LIBRARY_DIR="$bundlelibs"

resolve_links() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  [[ " ${VISITED[*]} " =~ " ${file} " ]] && return

  VISITED+=("$file")

  local links
  links=$(otool -L "$file" | tail -n +2 | awk '{print $1}')

  while IFS= read -r lib; do
    local resolved=""

    # Special case: @rpath/libsfml*
    if [[ "$lib" == @rpath/libsfml* ]]; then
      local libfile="${lib#@rpath/}"
      local sfml_candidate="am/obj/sfml/install/lib/$libfile"
      if [[ -f "$sfml_candidate" ]]; then
        resolved="$sfml_candidate"
        echo "Resolved SFML override: $lib -> $resolved"
      fi
    fi

    # Try pkg-config if still unresolved
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local libfile="${lib#@rpath/}"
      local base="${libfile%%.dylib*}"
      base="${base%%.*}"
      echo "Running pkg-config --libs-only-L for: $base"
      local pkg_lib
      pkg_lib=$(pkg-config --libs-only-L "$base" 2>/dev/null || true)
      echo "pkg-config result for $base: $pkg_lib"

      if [[ -n "$pkg_lib" ]]; then
        local pkg_dir="${pkg_lib#-L}"
        local candidate="$pkg_dir/$libfile"
        if [[ -f "$candidate" ]]; then
          resolved="$candidate"
        fi
      fi
    fi

    # Try absolute path
    if [[ -z "$resolved" && -f "$lib" ]]; then
      resolved="$lib"
    fi

    # Try rpaths
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local rpaths
      rpaths=$(otool -l "$file" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" {r=1}
        r && $1 == "path" {print $2; r=0}
      ')
      for rpath in $rpaths; do
        local candidate="$rpath/${lib#@rpath/}"
        if [[ -f "$candidate" ]]; then
          resolved="$candidate"
          break
        fi
      done
    fi

    if [[ -n "$resolved" && ! " ${RESOLVED[*]} " =~ " ${resolved} " ]]; then
      RESOLVED+=("$resolved")
      resolve_links "$resolved"
    fi
  done <<< "$links"
}

resolve_links "$attractname"

# STEP 3 - COPY LIBRARIES
echo "STEP 3 - COPYING LIBRARIES TO BUNDLE"

for lib in "${RESOLVED[@]}"; do
  lib_name=$(basename "$lib")
  if [[ ! -f "$LIBRARY_DIR/$lib_name" ]]; then
    echo "Copying $lib to $LIBRARY_DIR/$lib_name"
    cp "$lib" "$LIBRARY_DIR/$lib_name"
  fi
done

# STEP 4 - FIX INTERNAL LINKS IN BUNDLED LIBRARIES
echo "STEP 4 - FIXING INTERNAL LIBRARY LINKS"

for lib in "$LIBRARY_DIR"/*.dylib; do
  echo "Processing $lib"
  linked_libs=$(otool -L "$lib" | tail -n +2 | awk '{print $1}')

  while IFS= read -r dep; do
    dep_base=$(basename "$dep")
    local_target="@executable_path/../libs/$dep_base"

    if [[ "$dep" == @rpath/* || "$dep" == /opt/homebrew/* || -f "$LIBRARY_DIR/$dep_base" ]]; then
      echo "  Rewriting $dep -> $local_target"
      chmod +w "$lib"
      install_name_tool -change "$dep" "$local_target" "$lib"
      chmod -w "$lib"
    fi
  done <<< "$linked_libs"
done

# STEP 5 - FIX LINKS IN EXECUTABLE
echo "STEP 5 - FIXING EXECUTABLE LIBRARY LINKS"

linked_libs=$(otool -L "$attractname" | tail -n +2 | awk '{print $1}')

while IFS= read -r dep; do
  dep_base=$(basename "$dep")
  local_target="@executable_path/../libs/$dep_base"

  if [[ "$dep" == @rpath/* || "$dep" == /opt/homebrew/* || -f "$LIBRARY_DIR/$dep_base" ]]; then
    echo "  Rewriting $dep -> $local_target"
    chmod +w "$attractname"
    install_name_tool -change "$dep" "$local_target" "$attractname"
    chmod -w "$attractname"
  fi
done <<< "$linked_libs"

# Add rpath if needed
echo "Adding @executable_path/../libs rpath to executable"
install_name_tool -add_rpath "@executable_path/../libs" "$attractname" || true

echo "✅ All libraries copied and relinked. App bundle ready at: $bundlehome"
