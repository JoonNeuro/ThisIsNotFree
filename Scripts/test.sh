#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift test --scratch-path .build-tests --cache-path .build/cache --manifest-cache local --disable-sandbox
zsh Scripts/test-signal.sh
clang -fobjc-arc -mmacosx-version-min=14.2 -I Sources/MixerCore/include \
    -framework Foundation -framework IOKit Sources/MixerCore/SystemCore.m \
    Tests/SystemTelemetryTest.m -o .build/system-telemetry-test
.build/system-telemetry-test
