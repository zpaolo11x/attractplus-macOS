#!/bin/bash

# Usage: ./recursive-dylib-deps.sh /path/to/binary

if [ -z "$1" ]; then
  echo "Usage: $0 <binary>"
  exit 1
fi

BINARY="$1"
VISITED=()
RESOLVED=()

# Function to resolve and store libraries recursively
resolve_links() {
  local file="$1"

  [[ ! -f "$file" ]] && return
  [[ " ${VISITED[*]} " =~ " ${file} " ]] && return

  VISITED+=("$file")

  local links
  links=$(otool -L "$file" | tail -n +2 | awk '{print $1}')

  while IFS= read -r lib; do
    local resolved=""

    # --- Special case for libsfml ---
    if [[ "$lib" == @rpath/libsfml* ]]; then
      for candidate in am/obj/sfml/install/lib/"${lib#@rpath/}"; do
        if [[ -f "$candidate" ]]; then
          resolved="$candidate"
          echo "Resolved special case for SFML: $lib -> $resolved"
          break
        fi
      done
    fi

    # --- pkg-config for general @rpath ---
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local base_lib="${lib#@rpath/}"
      base_lib="${base_lib%%.*}"  # Remove suffix after first .

      echo "Running pkg-config --libs-only-L for: $base_lib"
      local pkg_lib
      pkg_lib=$(pkg-config --libs-only-L "$base_lib" 2>/dev/null)

      echo "pkg-config result for $base_lib: $pkg_lib"

      if [[ -n "$pkg_lib" ]]; then
        resolved="${pkg_lib#-L}/$base_lib.dylib"
      fi
    elif [[ -f "$lib" ]]; then
      resolved="$lib"
    fi

    # --- Try manual LC_RPATH fallback ---
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local rpaths
      rpaths=$(otool -l "$file" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" {r=1}
        r && $1 == "path" {print $2; r=0}
      ')

      for rpath in $rpaths; do
        candidate="${rpath}/${lib#@rpath/}"
        if [[ -f "$candidate" ]]; then
          resolved="$candidate"
          break
        fi
      done
    fi

    # Store resolved path if unique
    if [[ -n "$resolved" && ! " ${RESOLVED[*]} " =~ " ${resolved} " ]]; then
      RESOLVED+=("$resolved")
      resolve_links "$resolved"
    fi
  done <<< "$links"
}

# Start
resolve_links "$BINARY"

# Final output
echo "Resolved libraries:"
for lib in "${RESOLVED[@]}"; do
  echo "$lib"
done
