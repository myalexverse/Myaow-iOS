#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d "${TMPDIR:-/tmp}/myaow-validation.XXXXXX")
trap 'rm -rf "$validation_dir"' EXIT
node_binary=${NODE_BINARY:-node}
python3 Scripts/Tests/MaullidosAudioChecks.py
xcrun swiftc Myaow/Core/Nudge/MyaowNudgePolicy.swift Scripts/Tests/NudgePolicyChecks.swift -o "$validation_dir/nudge-policy"
"$validation_dir/nudge-policy"
xcrun swiftc Myaow/Core/Calling/CallVoiceLevel.swift Scripts/Tests/CallVoiceLevelChecks.swift -o "$validation_dir/call-voice"
"$validation_dir/call-voice"
xcrun swiftc Myaow/Core/Calling/CallResourcePreparation.swift Scripts/Tests/CallPreparationChecks.swift -o "$validation_dir/call-preparation"
"$validation_dir/call-preparation"
xcrun swiftc Myaow/Core/Calling/VideoCallFilter.swift Scripts/Tests/PortalSessionChecks.swift -o "$validation_dir/portal-session"
"$validation_dir/portal-session"
xcrun swiftc Myaow/DesignSystem/Mascot/MyaowCatState.swift Myaow/DesignSystem/Mascot/MyaowCatSpeechMotion.swift Scripts/Tests/CatSpeechChecks.swift -o "$validation_dir/cat-speech"
"$validation_dir/cat-speech"
xcrun swiftc Myaow/DesignSystem/Mascot/MyaowCatState.swift Myaow/DesignSystem/Mascot/MyaowCatMotion.swift Scripts/Tests/CatMotionChecks.swift -o "$validation_dir/cat-motion"
"$validation_dir/cat-motion"
xcrun swiftc Myaow/Core/Storage/CustomStickerImage.swift Scripts/Tests/CustomStickerImageChecks.swift -o "$validation_dir/custom-stickers"
"$validation_dir/custom-stickers"
xcrun swiftc Myaow/Core/Calling/CallSignalFailurePolicy.swift Scripts/Tests/CallSignalFailureChecks.swift -o "$validation_dir/call-failure"
"$validation_dir/call-failure"
common=(
  Myaow/Core/Identity/UserIdentity.swift
  Myaow/Core/Identity/IdentityVault.swift
  Myaow/Core/Crypto/CryptoService.swift
  Myaow/Core/Crypto/KeychainSecurityService.swift
  Myaow/Core/Crypto/SecureMessageEnvelope.swift
  Myaow/Core/Crypto/SecureMessageMutation.swift
  Myaow/Core/Crypto/EncryptedAttachment.swift
)
xcrun swiftc "${common[@]}" Scripts/Tests/CriticalSecurityChecks.swift -o "$validation_dir/security"
"$validation_dir/security"
xcrun swiftc "${common[@]}" Myaow/Core/Calling/VerifiedCallSignal.swift Scripts/Tests/CallSignalChecks.swift -o "$validation_dir/call-signal"
"$validation_dir/call-signal"
xcrun swiftc "${common[@]}" Myaow/Core/Storage/{ModelSchema,MomentModel,MyaowSchemaVersions,MyaowStorageController,MessageDeliveryStatus,MessageOutbox,SecureMutationStore,MessageReactionStore,TaskEvidenceStore,OutgoingAttachmentStore,MyaowSticker,ChatHistoryQuery}.swift Scripts/Tests/PersistenceChecks.swift -o "$validation_dir/persistence"
xcrun swiftc "${common[@]}" Myaow/Core/Storage/{ModelSchema,MessageDeliveryStatus,MessageOutbox,ChatDecorationStore}.swift Myaow/DesignSystem/Wallpapers/ChatDecoration.swift Scripts/Tests/ChatDecorationChecks.swift -o "$validation_dir/decorations"
xcrun swiftc Myaow/DesignSystem/Wallpapers/WallpaperVideoPlayback.swift Scripts/Tests/WallpaperPlaybackChecks.swift -o "$validation_dir/wallpaper-playback"
"$validation_dir/wallpaper-playback"
"$validation_dir/decorations"
"$validation_dir/persistence"
xcrun swiftc Myaow/Core/Radio/RadioPacket.swift Scripts/Tests/RadioChecks.swift -o "$validation_dir/radio"
"$validation_dir/radio"
xcrun swiftc Myaow/Core/Audio/RadioSoundDesign.swift Scripts/Tests/RadioSoundChecks.swift -o "$validation_dir/radio-sounds"
"$validation_dir/radio-sounds"
xcrun swiftc Myaow/Core/Radio/RadioTurnState.swift Scripts/Tests/RadioTurnChecks.swift -o "$validation_dir/radio-turns"
"$validation_dir/radio-turns"
xcrun swiftc Myaow/DesignSystem/Mascot/MyaowCatState.swift Myaow/Features/Groups/Models/GroupMissionModel.swift Myaow/Features/Groups/Models/GroupTaskFocus.swift Scripts/Tests/GroupTaskFocusChecks.swift -o "$validation_dir/group-focus"
xcrun swiftc Myaow/DesignSystem/Mascot/MyaowCatState.swift Myaow/Features/Groups/Models/GroupMissionModel.swift Myaow/Features/Groups/Models/GroupTaskFocus.swift Myaow/Features/Groups/Models/GroupProjectPlan.swift Scripts/Tests/GroupProjectChecks.swift -o "$validation_dir/group-project"
"$validation_dir/group-project"
"$validation_dir/group-focus"
xcrun swiftc Myaow/DesignSystem/Mascot/MyaowCatState.swift Myaow/Features/Groups/Models/GroupMissionModel.swift Myaow/Features/Groups/Models/GroupSpaceModel.swift Scripts/Tests/GroupTaskPolicyChecks.swift -o "$validation_dir/group-policy"
"$validation_dir/group-policy"
xcrun swiftc Myaow/Core/Radio/RadioPacket.swift Myaow/Core/Radio/RadioContactSecurity.swift Scripts/Tests/RadioPrivacyChecks.swift -o "$validation_dir/radio-privacy"
"$validation_dir/radio-privacy"
xcrun swiftc Myaow/Core/Radio/RadioPCMCodec.swift Scripts/Tests/RadioAudioChecks.swift -o "$validation_dir/radio-audio"
"$validation_dir/radio-audio"
for configuration in debug release; do
  if [[ "$configuration" == debug ]]; then
    xcrun swiftc -DDEBUG Myaow/Core/Identity/RegistrationInput.swift Scripts/Tests/RegistrationInputChecks.swift -o "$validation_dir/registration-$configuration"
  else
    xcrun swiftc Myaow/Core/Identity/RegistrationInput.swift Scripts/Tests/RegistrationInputChecks.swift -o "$validation_dir/registration-$configuration"
  fi
  "$validation_dir/registration-$configuration"
done
xcrun swiftc "${common[@]}" Myaow/Core/Identity/RelayAuthentication.swift Myaow/Core/Identity/RegistrationInput.swift Myaow/Core/Backend/SupabaseClient.swift Scripts/Tests/SupabaseRouteChecks.swift -o "$validation_dir/supabase-routes"
"$validation_dir/supabase-routes"
xcrun swiftc Myaow/Core/Backend/SupabaseSyncPolicy.swift Scripts/Tests/SupabaseSyncChecks.swift -o "$validation_dir/supabase-sync"
"$validation_dir/supabase-sync"
xcrun swiftc "${common[@]}" Myaow/Core/Storage/GroupReceiptStore.swift Scripts/Tests/GroupReceiptChecks.swift -o "$validation_dir/group-receipts"
"$validation_dir/group-receipts"
xcrun swiftc "${common[@]}" Myaow/Core/Storage/GroupMessageOutbox.swift Scripts/Tests/GroupOutboxChecks.swift -o "$validation_dir/group-outbox"
"$validation_dir/group-outbox"
xcrun swiftc "${common[@]}" Myaow/Core/Identity/RelayAuthentication.swift Myaow/Core/Backend/SupabaseClient.swift Myaow/Core/Backend/SupabaseMediaClient.swift Myaow/Core/Storage/PendingMediaUploadStore.swift Scripts/Tests/PendingMediaChecks.swift -o "$validation_dir/pending-media"
"$validation_dir/pending-media"
xcrun swiftc "${common[@]}" Myaow/Core/Identity/RelayAuthentication.swift Myaow/Core/Backend/SupabaseClient.swift Myaow/Core/Backend/SupabaseMediaClient.swift Myaow/Core/Storage/PendingMediaUploadStore.swift Scripts/Tests/AttachmentRetryChecks.swift -o "$validation_dir/attachment-retry"
"$validation_dir/attachment-retry"
"$node_binary" --test Server/test_supabase_push.mjs
"$node_binary" --test Server/test_registration.js Server/test_durable_relay.js Server/test_collaboration.js Server/test_secure_scheduler.js Server/test_push_calls.js Server/test_beta_operations.js Server/test_beta_http.js Server/test_beta_configuration.js Server/test_supabase_gateway.mjs Server/test_supabase_media.mjs Server/test_supabase_calls.mjs
xcrun swiftc "${common[@]}" Myaow/Core/Identity/RelayAuthentication.swift Scripts/Tests/NativeRelayChecks.swift -o "$validation_dir/native-relay"
MYAOW_NATIVE_CHECKS="$validation_dir/native-relay" "$node_binary" --test Server/test_native_relay.js
