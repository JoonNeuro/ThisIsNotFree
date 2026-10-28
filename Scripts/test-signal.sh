#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
clang -fobjc-arc -mmacosx-version-min=14.2 \
    -I Sources/MixerCore/include \
    -framework Foundation -framework CoreAudio \
    Tests/SignalPathTest.m -o .build/signal-path-test
.build/signal-path-test
