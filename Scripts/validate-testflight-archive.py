"""Check the actual distribution archive, without reading credentials."""
import plistlib
import subprocess
import sys
from pathlib import Path

archive = Path(sys.argv[1])
app = archive / "Products/Applications/Myaow.app"
with (app / "Info.plist").open("rb") as source:
    info = plistlib.load(source)
expected = {
    "CFBundleIdentifier": "com.ScendLabs.Myaow",
    "MyaowRelayURL": "https://your-project-ref.supabase.co/functions/v1/myaow-api",
    "MyaowPushEnvironment": "production",
}
for key, value in expected.items():
    assert info.get(key) == value, f"Unexpected {key}: {info.get(key)!r}"
assert str(info.get("MyaowBetaInviteRequired")).lower() in ("yes", "true", "1"), "Invitations must be required"
assert "ITSAppUsesNonExemptEncryption" not in info, "Complete export compliance in App Store Connect first"
assert (app / "PrivacyInfo.xcprivacy").is_file(), "Privacy manifest is missing"
for sound in ('classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration'):
    assert (app / f'myaow-{sound}.wav').is_file(), f"Missing bundled APNs sound: {sound}"
assert (archive / "dSYMs/Myaow.app.dSYM").is_dir(), "App debug symbols are missing"
assert not any(app.rglob("*.p8")), "Private signing key must never be bundled"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], check=True, capture_output=True)
entitlements = plistlib.loads(entitlements.stdout)
assert entitlements.get("com.apple.developer.team-identifier") == "YOUR_TEAM_ID"
assert entitlements.get("application-identifier") == "YOUR_TEAM_ID.com.ScendLabs.Myaow"
print(f"Verified Myaow {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}); iOS {info['MinimumOSVersion']}+")
print("Backend, invitations, bundled privacy manifest, app symbols and archive signature verified.")
print("Archive APNs entitlement:", entitlements.get("aps-environment"), "(recheck production after distribution export)")
