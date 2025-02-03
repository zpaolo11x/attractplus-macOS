#!/bin/bash

if [[ -n "$1" ]]
then
    branch="-b $1"
else
    branch="fix_macOS_builder"
fi

export PKG_CONFIG_PATH=/usr/local/pkgconfig

echo Creating Folders
rm -Rf $HOME/buildattractTEST
mkdir $HOME/buildattractTEST

echo Cloning attractplus
git clone $branch http://github.com/zpaolo11x/attractplus-macOS $HOME/buildattractTEST/attractplus

cd $HOME/buildattractTEST/attractplus

LASTTAG=$(git describe --tag --abbrev=0)
VERSION=$(git describe --tag | sed 's/-[^-]\{8\}$//')
BUNDLEVERSION=${VERSION//[v-]/.}; BUNDLEVERSION=${BUNDLEVERSION#"."}
SHORTVERSION=${LASTTAG//v/}

NPROC=$(getconf _NPROCESSORS_ONLN)

echo Building attractplus
make clean
eval make -j${NPROC} STATIC=0 VERBOSE=1 prefix=..


bash util/osx/appbuilder.sh $HOME/buildattractTEST $HOME/buildattractTEST/attractplus yes
