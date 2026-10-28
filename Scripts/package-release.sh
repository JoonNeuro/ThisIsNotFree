#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

: "${MAC_AUDIO_MIXER_BUNDLE_ID:?Set a unique bundle identifier, for example com.yourname.MacAudioMixer}"
: "${MAC_AUDIO_MIXER_VERSION:?Set a release version, for example 0.1.0}"
: "${MAC_AUDIO_MIXER_SIGNING_IDENTITY:?Set your Developer ID Application certificate name}"
: "${MAC_AUDIO_MIXER_NOTARY_PROFILE:?Set a notarytool Keychain profile name}"

if [[ "$MAC_AUDIO_MIXER_BUNDLE_ID" == com.example.* || "$MAC_AUDIO_MIXER_SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
    print -u2 -- "Release requires a non-example bundle ID and a Developer ID Application signing identity."
    exit 1
fi

zsh Scripts/build-app.sh
app="${PWD}/dist/ThisIsNotFree.app"
archive="${PWD}/dist/ThisIsNotFree-${MAC_AUDIO_MIXER_VERSION}-macOS.zip"
upload="${PWD}/dist/ThisIsNotFree-${MAC_AUDIO_MIXER_VERSION}-notary.zip"

codesign --verify --strict --deep --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$upload"
notary_result=$(xcrun notarytool submit "$upload" --keychain-profile "$MAC_AUDIO_MIXER_NOTARY_PROFILE" --wait --output-format json)
notary_status=$(print -r -- "$notary_result" | plutil -extract status raw -)
if [[ "$notary_status" != "Accepted" ]]; then
    print -u2 -- "$notary_result"
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
ditto -c -k --keepParent "$app" "$archive"
rm "$upload"
shasum -a 256 "$archive"
print -r -- "$archive"
