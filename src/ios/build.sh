#!/bin/bash -e

path=`dirname $0`

#
# Checks exit value for error
# 
checkError() {
    if [ $? -ne 0 ]
    then
        echo "Exiting due to errors (above)"
        exit -1
    fi
}

# 
# Canonicalize relative paths to absolute paths
# 
pushd $path > /dev/null
dir=`pwd`
path=$dir
popd > /dev/null

# 
# Build plugin
# 
CONFIG=Release

# Cleans all
xcodebuild -project "$path/Plugin.xcodeproj" -configuration $CONFIG clean

# iOS
xcodebuild -project "$path/Plugin.xcodeproj" -alltargets -configuration $CONFIG  -sdk iphoneos
checkError

# Xcode Simulator
xcodebuild -project "$path/Plugin.xcodeproj" -alltargets -configuration $CONFIG -sdk iphonesimulator
checkError

# create universal binary
shopt -s nullglob  # don't enter loop if no files found
shopt -s dotglob   # we don't want '.' dirs/files

IPHONEOS_DIR="$path"/build/$CONFIG-iphoneos
IPHONESIM_DIR="$path"/build/$CONFIG-iphonesimulator
UNIVERSAL_DIR="$path"/build/$CONFIG-universal

if [ ! -d "$UNIVERSAL_DIR" ]; then
	mkdir "$UNIVERSAL_DIR"
fi

# pushd "$IPHONEOS_DIR"
# for staticlib in *.a; do
# 	lipo -create "$IPHONEOS_DIR"/$staticlib "$IPHONESIM_DIR"/$staticlib -output "$UNIVERSAL_DIR"/$staticlib
# done
# popd

fat="$path/libs/libTenjinSDKUniversal.a"
lipo -extract armv7 -extract arm64 "$fat" -output "$IPHONEOS_DIR/libTenjinSDKUniversal.a"
lipo -extract i386 -extract x86_64 "$fat" -output "$IPHONESIM_DIR/libTenjinSDKUniversal.a"
