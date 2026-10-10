#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -swift-version 5 -target arm64-apple-macos13.0 Sources/Audio.swift Sources/Bridge.swift Sources/Wire.swift Sources/NetworkDetails.swift Sources/Transport.swift Sources/LocalOutput.swift Sources/SleepStatus.swift Tests/main.swift -o build/BridgeTests
build/BridgeTests
