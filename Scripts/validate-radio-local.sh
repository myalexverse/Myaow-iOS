#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
radio_validation_dir=$(mktemp -d "${TMPDIR:-/tmp}/myaow-radio-validation.XXXXXX")
trap 'rm -rf "$radio_validation_dir"' EXIT
xcrun swiftc Myaow/Core/Radio/RadioPacket.swift Myaow/Core/Radio/RadioContactSecurity.swift Myaow/Core/Radio/LocalRadioTransport.swift Scripts/Tests/RadioTransportChecks.swift -o "$radio_validation_dir/local-radio"
"$radio_validation_dir/local-radio"
