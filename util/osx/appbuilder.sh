#!/bin/bash

echo STEP 1 - PREPARE BUNDLE FOLDERS

#CALL WITH "artifacts" as buildpath for CI
buildpath=${1:-"artifacts"}

echo $buildpath

# Define folder path variables
bundlehome="$buildpath/Attract Mode Plus.app"
bundlecontent="$bundlehome"/Contents
bundlelibs="$bundlecontent"/libs

rm -Rf "$bundlehome"
mkdir "$bundlehome"
mkdir "$bundlecontent"
mkdir "$bundlelibs"
mkdir "$bundlecontent"/MacOS
mkdir "$bundlecontent"/Resources
mkdir "$bundlecontent"/share
mkdir "$bundlecontent"/share/attract

#CALL WITH "am" AS PARAMETER 2
basedir=${2:-"am"}
attractname="$basedir/attractplus"

echo STEP 2 - COLLECT AND FIX LINKED LIBRARIES

# Initialize arrays
fr_lib=()
to_lib=()
fullarray=()
updatearray=("$attractname")

# Recursively find and resolve all linked libraries
while [ ${#updatearray[@]} -gt 0 ]; do
    new_updatearray=()
    for bin in "${updatearray[@]}"; do
        echo "Scanning: $(basename "$bin")"

        linked_libs=( $(otool -L "$bin" | awk '{print $1}' | grep -E '^@rpath|/opt|/usr/local') )

        for lib in "${linked_libs[@]}"; do
            orig_lib="$lib"
            # Attempt to resolve @rpath to actual paths
            if [[ "$lib" == @rpath/* ]]; then
                libname=$(basename "$lib")
                foundpath=$(find "$basedir" -name "$libname" -type f 2>/dev/null | head -n 1)
                if [[ -n "$foundpath" ]]; then
                    if [[ ! " ${fr_lib[*]} " =~ " $lib " ]]; then
                        fr_lib+=("$lib")
                        to_lib+=("$foundpath")
                        echo "  Resolved $lib → $foundpath"
                        lib="$foundpath"
                    fi
                else
                    echo "  WARNING: Could not resolve $lib"
                    continue
                fi
            fi

            # Track the library if not already processed
            if [[ ! " ${fullarray[*]} " =~ " $lib " ]]; then
                fullarray+=("$lib")
                new_updatearray+=("$lib")
            fi
        done
    done
    updatearray=("${new_updatearray[@]}")
done

# Build sed command filters from fr_lib → to_lib
commands=("")
for enum in "${!fr_lib[@]}"; do
    commands+=(s/$(sed 's/\//\\\//g' <<< "${fr_lib[$enum]}")/$(sed 's/\//\\\//g' <<< "${to_lib[$enum]}")/g)
done

# Apply sed filters to fullarray
for commandline in "${commands[@]}"; do
    fullarray=($(sed "$commandline" <<< "${fullarray[@]}"))
done


# Copy linked libraries to bundle folder, using fullarray that has the whole list of paths
for str in ${fullarray[@]}; do
   echo copying $str
   cp -n $str "$bundlelibs"/
done

# Change paths for all copied libraries
libsarray=( $(ls "$bundlecontent"/libs) )
for str in ${libsarray[@]}; do
   echo fixing $str
   subarray=( $(otool -L "$bundlelibs"/$str | tail -n +2 | grep '/opt/homebrew\|@rpath' | awk -F' ' '{print $1}') )
   subarray_fix=( $(otool -L "$bundlelibs"/$str | tail -n +2 | grep '/opt/homebrew\|@rpath' | awk -F' ' '{print $1}') )

	#Apply correction filters to all libraries
	for commandline in ${commands[@]}; do
		subarray_fix=($(sed "$commandline" <<< "${subarray_fix[@]}"))
	done

	for enum in ${!subarray[@]}; do
      str3=$( basename "${subarray_fix[enum]}" )
      str2="${subarray[enum]}"
      install_name_tool -change $str2 @loader_path/../libs/$str3 "$bundlelibs"/$str 2>/dev/null
   done
   install_name_tool -id @loader_path/../libs/$str "$bundlelibs"/$str 2>/dev/null
	#codesign --force -s - "$bundlelibs"/$str
done

echo STEP 3 - POPULATE BUNDLE FOLDER

# Copy assets to bundle folder
# cp -r $basedir/config "$bundlecontent"/
cp -a $basedir/config/ "$bundlecontent"/share/attract
cp -a $basedir/attractplus "$bundlecontent"/MacOS/
cp -a $basedir/util/osx/attractplus.icns "$bundlecontent"/Resources/
cp -a $basedir/util/osx/launch.sh "$bundlecontent"/MacOS/
#cp "$bundlelibs"/libfreetype.6.dylib "$bundlelibs"/freetype

# Prepare plist file
LASTTAG=$(git -C $basedir/ describe --tag --abbrev=0)
VERSION=$(git -C $basedir/ describe --tag | sed 's/-[^-]\{8\}$//')
BUNDLEVERSION=${VERSION//[v-]/.}; BUNDLEVERSION=${BUNDLEVERSION#"."}
SHORTVERSION=${LASTTAG//v/}

sed -e 's/%%SHORTVERSION%%/'${SHORTVERSION}'/' -e 's/%%BUNDLEVERSION%%/'${BUNDLEVERSION}'/' $basedir/util/osx/Info.plist > "$bundlecontent"/Info.plist

echo STEP 4 - FIX ATTRACTPLUS EXECUTABLE

# Update rpath for attractplus
install_name_tool -add_rpath "@executable_path/../libs/" "$bundlecontent"/MacOS/attractplus

# List libraries linked in attractplus
attractlibs=( $(otool -L $attractname | tail -n +2 | grep '@loader_path\|@loader_path/../../../../opt\|/usr/local\|/opt/homebrew\|@rpath' | awk -F' ' '{print $1}') )

# Apply new links to libraries
for str in ${attractlibs[@]}; do
   str2=$( basename "$str" )
   install_name_tool -change $str @loader_path/../libs/$str2 "$bundlecontent"/MacOS/attractplus
done
#codesign --force -s - "$bundlecontent"/MacOS/attractplus
echo STEP 5 - RENAME ARTIFACT TO v${SHORTVERSION}

newappname="$buildpath/Attract-Mode Plus v${SHORTVERSION}.app"
mv "$bundlehome" "$newappname"

signapp=${3:-"no"}

if [[ $signapp == "yes" ]]
then
	echo STEP 6 - AD HOC SIGNING
	libsarray=( $(ls "$newappname/Contents/libs") )
	for str in ${libsarray[@]}; do
		codesign --force -s - "$newappname/Contents/libs/$str"
	done
	codesign --force -s - "$newappname/Contents/MacOS/attractplus"
	codesign --force -s - "$newappname"
fi

echo ALL DONE
