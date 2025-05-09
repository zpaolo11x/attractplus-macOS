#!/bin/bash

# Usage: ./resolve-dylibs.sh /path/to/binary

if [ -z "$1" ]; then
  echo "Usage: $0 <binary>"
  exit 1
fi

BINARY="$1"
VISITED=()
RESOLVED=()

resolve_links() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  [[ " ${VISITED[*]} " =~ " ${file} " ]] && return

  VISITED+=("$file")

  local links
  links=$(otool -L "$file" | tail -n +2 | awk '{print $1}')

  while IFS= read -r lib; do
    local resolved=""

    # --- Special case: @rpath/libsfml* -> am/obj/sfml/install/lib ---
    if [[ "$lib" == @rpath/libsfml* ]]; then
      local libfile="${lib#@rpath/}"
      local sfml_candidate="am/obj/sfml/install/lib/$libfile"
      if [[ -f "$sfml_candidate" ]]; then
        resolved="$sfml_candidate"
        echo "Resolved SFML override: $lib -> $resolved"
      fi
    fi

    # --- Try pkg-config if still unresolved and lib is @rpath/... ---
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local libfile="${lib#@rpath/}"
      local base="${libfile%%.dylib*}"         # e.g. libwebp.7 or libwebp.0.1
      base="${base%%.*}"                       # extract just the base, e.g. libwebp
      echo "Running pkg-config --libs-only-L for: $base"
      local pkg_lib
      pkg_lib=$(pkg-config --libs-only-L "$base" 2>/dev/null)
      echo "pkg-config result for $base: $pkg_lib"

      if [[ -n "$pkg_lib" ]]; then
        local pkg_dir="${pkg_lib#-L}"
        local candidate="$pkg_dir/$libfile"
        if [[ -f "$candidate" ]]; then
          resolved="$candidate"
        fi
      fi
    fi

    # --- Try absolute path as-is ---
    if [[ -z "$resolved" && -f "$lib" ]]; then
      resolved="$lib"
    fi

    # --- Try rpath entries in binary ---
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

    # --- Store and recurse ---
    if [[ -n "$resolved" && ! " ${RESOLVED[*]} " =~ " ${resolved} " ]]; then
      RESOLVED+=("$resolved")
      resolve_links "$resolved"
    fi
  done <<< "$links"
}

# Start recursion
resolve_links "$BINARY"

# Final output
echo -e "\nResolved libraries:"
for lib in "${RESOLVED[@]}"; do
  echo "$lib"
done
