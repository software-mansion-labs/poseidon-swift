#!/usr/bin/env bash

set -e

ios_version=$(xcrun --sdk iphoneos --show-sdk-platform-version)
macosx_version=$(xcrun --sdk macosx --show-sdk-platform-version)

ios_min_version="13.0"
macosx_min_version="12.0"

# When changing targets or sdk_names array, make sure you update
# indexes in fat binary creation at the end of the file.

targets=(
  "arm64-apple-ios"
  "arm64-apple-ios-simulator"
  "x86_64-apple-ios-simulator"
  "arm64-apple-darwin"
  "x86_64-apple-darwin"
)

sdk_names=(
  "iphoneos$ios_version"
  "iphonesimulator$ios_version"
  "iphonesimulator$ios_version"
  "macosx$macosx_version"
  "macosx$macosx_version"
)

mkdir -p Binaries
mkdir -p Headers

pushd poseidon

targets_size=${#targets[@]}

for (( i=0; i < $targets_size; i++ )); do
  mkdir -p Build/${targets[i]}

  pushd Build/${targets[i]}

  sdk_sysroot="$(xcrun --sdk "${sdk_names[i]}" --show-sdk-path)"

  if [[ "${sdk_names[i]}" == macosx* ]]; then
    system_name="Darwin";
    min_version="$macosx_min_version";
  else 
    system_name="iOS";
    min_version="$ios_min_version";
  fi

  # Get the architecture prefix from the target triple
  arch=$(echo "${targets[i]}" | cut -d'-' -f 1)

  cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING="1" \
    -DCMAKE_C_COMPILER_WORKS="1" \
    -DCMAKE_CXX_COMPILER_WORKS="1" \
    -DCMAKE_SYSTEM_NAME="$system_name" \
    -DCMAKE_OSX_SYSROOT="$sdk_sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_version" \
    ../..

  popd

  make -C "Build/${targets[i]}"

  mkdir -p "../Binaries/${targets[i]}"
  cp "Build/${targets[i]}/libposeidon.dylib" "../Binaries/${targets[i]}/libposeidon.dylib"
done

popd

rm Headers/*.h || true
cp poseidon/sources//{poseidon.h,poseidon_rc.h,f251.h} Headers

build_command="xcodebuild -create-xcframework"

# Please note, that getting values from arrays below is fixed, so make sure to update
# it when doing changes to targets or sdk_names arrays.

mkdir -p Frameworks/{"${sdk_names[0]}/libposeidon.framework","${sdk_names[1]}/libposeidon.framework","${sdk_names[3]}/libposeidon.framework"}

lipo -create \
  "Binaries/${targets[0]}/libposeidon.dylib" \
  -output "Frameworks/${sdk_names[0]}/libposeidon.framework/libposeidon"

lipo -create  \
  "Binaries/${targets[1]}/libposeidon.dylib" \
  "Binaries/${targets[2]}/libposeidon.dylib" \
  -output "Frameworks/${sdk_names[1]}/libposeidon.framework/libposeidon"

lipo -create \
  "Binaries/${targets[3]}/libposeidon.dylib" \
  "Binaries/${targets[4]}/libposeidon.dylib" \
  -output "Frameworks/${sdk_names[3]}/libposeidon.framework/libposeidon"

plist_cmd="/usr/libexec/PlistBuddy"

for binary in $(printf "%s\n" "${sdk_names[@]}" | sort -u); do
  install_name_tool -id @rpath/libposeidon.framework/libposeidon "./Frameworks/$binary/libposeidon.framework/libposeidon"

  mkdir -p "./Frameworks/$binary/libposeidon.framework/Headers"

  cp ./Headers/*.h "./Frameworks/$binary/libposeidon.framework/Headers"
  cp ./Info.plist "./Frameworks/$binary/libposeidon.framework/Info.plist"

  if [[ "${binary}" == macosx* ]]; then
    min_version="$macosx_min_version";
  else 
    min_version="$ios_min_version";
  fi

  $plist_cmd -c "Add :MinimumOSVersion string $min_version" "./Frameworks/$binary/libposeidon.framework/Info.plist"

  build_command+=" -framework Frameworks/$binary/libposeidon.framework"
done

build_command+=" -output poseidon.xcframework"

eval $build_command
