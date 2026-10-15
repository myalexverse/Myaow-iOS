#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Separate simulator application; never changes the regular app's account,
# Keychain access group, defaults, relay URL or local conversation database.
pilot_output=${MYAOW_PILOT_DERIVED_DATA:-/private/tmp/myaow-supabase-pilot}
xcodebuild -project Myaow.xcodeproj -scheme Myaow -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$pilot_output" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- PRODUCT_BUNDLE_IDENTIFIER=com.ScendLabs.Myaow.SupabasePilot \
  INFOPLIST_KEY_CFBundleDisplayName='Myaow Pilot' \
  MYAOW_RELAY_URL=https://your-project-ref.supabase.co/functions/v1/myaow-api \
  MYAOW_BETA_INVITE_REQUIRED=YES build
