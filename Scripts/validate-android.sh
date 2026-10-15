#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/myaow-android.XXXXXX")"
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc -module-cache-path "$validation_dir/module-cache" \
  Myaow/Core/Identity/UserIdentity.swift Myaow/Core/Identity/IdentityVault.swift \
  Myaow/Core/Crypto/CryptoService.swift Myaow/Core/Crypto/KeychainSecurityService.swift \
  Myaow/Core/Crypto/SecureMessageEnvelope.swift Myaow/Core/Crypto/EncryptedAttachment.swift \
  Myaow/Core/Identity/RelayAuthentication.swift Android/interop/InteropFixtures.swift \
  -o "$validation_dir/interop"
"$validation_dir/interop" generate "$validation_dir/swift.json"
Android/gradlew -p Android :protocol:test :account:test :app:assembleDebug :app:lintDebug \
  -PswiftFixture="$validation_dir/swift.json" --console=plain "$@"
"$validation_dir/interop" verify Android/protocol/build/interop/android.json
