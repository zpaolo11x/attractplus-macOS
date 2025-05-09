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

  # Skip non-existent or already visited files
  [[ ! -f "$file" ]] && return
  [[ " ${VISITED[*]} " =~ " ${file} " ]] && return

  VISITED+=("$file")

  # Get linked libraries, skip the first line (binary name)
  local links
  links=$(otool -L "$file" | tail -n +2 | awk '{print $1}')

  while IFS= read -r lib; do
    # Resolve @rpath using pkg-config if available
    local resolved=""
    if [[ "$lib" == @rpath/* ]]; then
      # Strip the version suffix (e.g., .0.dylib) to get the base library name
      local base_lib="${lib#@rpath/}"
      base_lib="${base_lib%%.*}"  # Remove anything after the first period

      # Attempt pkg-config for @rpath
      echo "Running pkg-config --libs-only-L for: $base_lib"
      local pkg_lib
      pkg_lib=$(pkg-config --libs-only-L "$base_lib" 2>/dev/null)

      # Echo the pkg-config result
      echo "pkg-config result for $base_lib: $pkg_lib"

      if [[ -n "$pkg_lib" ]]; then
        # Strip the -L prefix and append the library name
        resolved="${pkg_lib#-L}/$base_lib.dylib"
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

    # Only add resolved paths to RESOLVED if not already added
    if [[ -n "$resolved" && ! " ${RESOLVED[*]} " =~ " ${resolved} " ]]; then
      RESOLVED+=("$resolved")
      resolve_links "$resolved"
    fi
  done <<< "$links"
}

# Start the resolution process
resolve_links "$BINARY"

# Now RESOLVED contains all the unique resolved libraries with their paths
echo "Libraries linked (with resolved paths):"
for lib in "${RESOLVED[@]}"; do
  echo "$lib"
done
