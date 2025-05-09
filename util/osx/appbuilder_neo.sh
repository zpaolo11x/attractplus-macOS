#!/bin/bash

set -euo pipefail

# STEP 1 - PREPARE BUNDLE FOLDERS

buildpath=${1:-"artifacts"}
echo "Build path: $buildpath"

bundlehome="$buildpath/Attract Mode Plus.app"
bundlecontent="$bundlehome/Contents"
bundlelibs="$bundlecontent/libs"

rm -Rf "$bundlehome"
mkdir -p "$bundlelibs" "$bundlecontent/MacOS" "$bundlecontent/Resources" "$bundlecontent/share/attract"

basedir=${2:-"am"}
attractname="$basedir/attractplus"

# STEP 2 - BUILD LIBRARY LIST RECURSIVELY

unresolved_paths=()
resolved_paths=()
seen_paths=()

resolve_rpath() {
  local lib="$1"
  local base="${lib#@rpath/}"

  # Handle custom SFML case
  if [[ "$base" == libsfml* ]]; then
    echo "$basedir/obj/sfml/install/lib/$base"
    return
  fi

  local pkg_output
  pkg_output=$(pkg-config --libs-only-L "$base" 2>/dev/null || true)
  echo "Running pkg-config --libs-only-L for: $base"
  echo "pkg-config result for $base: $pkg_output"

  if [[ "$pkg_output" == -L* ]]; then
    local dir="${pkg_output#-L}"
    echo "$dir/$base"
  else
    echo "$lib"  # unresolved fallback
  fi
}

process_binary() {
  local bin="$1"
  local deps
  deps=$(otool -L "$bin" | awk 'NR>1 {print $1}')

  while IFS= read -r dep; do
    if [[ "$dep" == @rpath/* || "$dep" == /opt/homebrew/* ]]; then
      local resolved=""
      if [[ "$dep" == @rpath/* ]]; then
        resolved=$(resolve_rpath "$dep")
      else
        resolved="$dep"
      fi

      if [[ -f "$resolved" && ! " ${seen_paths[@]} " =~ " $resolved " ]]; then
        unresolved_paths+=("$dep")
        resolved_paths+=("$resolved")
        seen_paths+=("$resolved")
        process_binary "$resolved"
      fi
    fi
  done <<< "$deps"
}

process_binary "$attractname"

# STEP 3 - COPY LIBRARIES TO BUNDLE AND SET INSTALL NAMES

copied_libs=()

for ((i=0; i<${#resolved_paths[@]}; i++)); do
  original="${unresolved_paths[$i]}"
  resolved="${resolved_paths[$i]}"
  target="$bundlelibs/$(basename "$resolved")"

  if [[ ! -f "$target" ]]; then
    echo "Copying $resolved to $target"
    cp "$resolved" "$target"
    copied_libs+=("$resolved")
  fi

  if [[ "$target" == *.dylib ]]; then
    echo "Setting install name for $(basename "$target")"
    chmod +w "$target"
    install_name_tool -id "@executable_path/../libs/$(basename "$target")" "$target"
  fi

  chmod -w "$target"
done

# STEP 4 - REWRITE LINKED PATHS IN COPIED LIBS

for lib in "$bundlelibs"/*.dylib; do
  linked_libs=$(otool -L "$lib" | awk 'NR>1 {print $1}')
  for ((i=0; i<${#unresolved_paths[@]}; i++)); do
    from="${unresolved_paths[$i]}"
    to="@executable_path/../libs/$(basename "${resolved_paths[$i]}")"
    if echo "$linked_libs" | grep -q "$from"; then
      echo "Rewriting $from -> $to in $lib"
      chmod +w "$lib"
      install_name_tool -change "$from" "$to" "$lib"
      chmod -w "$lib"
    fi
  done

  chmod -w "$lib"
done

# STEP 5 - REWRITE PATHS IN MAIN EXECUTABLE

for ((i=0; i<${#unresolved_paths[@]}; i++)); do
  from="${unresolved_paths[$i]}"
  to="@executable_path/../libs/$(basename "${resolved_paths[$i]}")"
  if otool -L "$attractname" | grep -q "$from"; then
    echo "Rewriting $from -> $to in $attractname"
    chmod +w "$attractname"
    install_name_tool -change "$from" "$to" "$attractname"
    chmod -w "$attractname"
  fi

done

echo "✅ All libraries copied and relinked. App bundle ready at: $bundlehome"
