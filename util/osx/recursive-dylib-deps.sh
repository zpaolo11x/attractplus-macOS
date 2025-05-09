#!/bin/bash

# Usage: ./recursive-dylib-deps.sh /path/to/binary

if [ -z "$1" ]; then
  echo "Usage: $0 <binary>"
  exit 1
fi

BINARY="$1"
VISITED=()
LIBRARY_ARRAY=()

# Function to resolve and store libraries recursively
resolve_links() {
  local file="$1"

  # Skip non-existent or already visited files
  [[ ! -f "$file" ]] && return
  [[ " ${VISITED[*]} " =~ " ${file} " ]] && return

  VISITED+=("$file")

  # Get linked libraries, skip the first line (binary name)
  local links
  links=$(otool -L "$file" | tail -n +2 | awk '{print $1}')

  while IFS= read -r lib; do
    # Filter for rpath and /opt/homebrew libraries
    if [[ "$lib" == @rpath* || "$lib" == /opt/homebrew/* ]]; then
      LIBRARY_ARRAY+=("$lib")
    fi

    # Resolve @rpath using pkg-config if available
    local resolved=""
    if [[ "$lib" == @rpath/* ]]; then
      # Attempt pkg-config for @rpath
      local pkg_lib
      pkg_lib=$(pkg-config --libs-only-L "${lib#@rpath/}" 2>/dev/null)

      if [[ -n "$pkg_lib" ]]; then
        resolved="$pkg_lib/${lib#@rpath/}"
      fi
    elif [[ -f "$lib" ]]; then
      resolved="$lib"
    fi

    # If pkg-config resolution fails, try manual resolution using otool -l and LC_RPATH
    if [[ -z "$resolved" && "$lib" == @rpath/* ]]; then
      local rpaths
      rpaths=$(otool -l "$file" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" {r=1}
        r && $1 == "path" {print $2; r=0}
      ')

      for rpath in $rpaths; do
        candidate="${rpath}/${lib#@rpath/}"
        if [ -f "$candidate" ]; then
          resolved="$candidate"
          break
        fi
      done
    fi

    # Recurse into resolved library
    if [[ -n "$resolved" ]]; then
      resolve_links "$resolved"
    fi
  done <<< "$links"
}

# Start the resolution process
resolve_links "$BINARY"

# Now LIBRARY_ARRAY contains all the libraries with their paths
echo "Libraries linked (with paths):"
for lib in "${LIBRARY_ARRAY[@]}"; do
  echo "$lib"
done
