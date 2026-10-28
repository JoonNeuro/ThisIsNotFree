#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build -c release --scratch-path .build --cache-path .build/cache --manifest-cache local --disable-sandbox
app="${PWD}/dist/ThisIsNotFree.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ! -f Resources/AppIcon.icns || Scripts/make-icon.swift -nt Resources/AppIcon.icns || Resources/Brand/MouthArtwork-v1.png -nt Resources/AppIcon.icns ]]; then
    swift Scripts/make-icon.swift .build/AppIcon.iconset Resources/AppIcon.icns
fi
cp .build/release/ThisIsNotFree "$app/Contents/MacOS/ThisIsNotFree"
rm -f "$app/Contents/MacOS/MacAudioMixer"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleIdentifier -string "${MAC_AUDIO_MIXER_BUNDLE_ID:-com.joonneuro.ThisIsNotFree}" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${MAC_AUDIO_MIXER_VERSION:-0.1.0}" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${MAC_AUDIO_MIXER_BUILD_NUMBER:-1}" "$app/Contents/Info.plist"
identity="${MAC_AUDIO_MIXER_SIGNING_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
print -r -- "$app"
