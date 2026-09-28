#!/bin/bash
# Executed only from the independently pinned trusted tools checkout.
set -euo pipefail
set +x
: "${TRUSTED_TOOLS_ROOT:?missing trusted tools checkout}"
: "${PACEPROMPT_RELEASE_SOURCE_ROOT:?missing candidate metadata checkout}"
VERIFIED_ARCHIVE="$RUNNER_TEMP/verified/PromptPace.xcarchive"
test -d "$VERIFIED_ARCHIVE"
tools="$TRUSTED_TOOLS_ROOT"
[[ "$RELEASE_TOOLS_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git -C "$tools" rev-parse HEAD)" = "$RELEASE_TOOLS_SHA"
unset PYTHONPATH PYTHONHOME
cd "$tools"
umask 077
test -n "$ASC_KEY_ID" && test -n "$ASC_ISSUER_ID" && test -n "$ASC_API_KEY_P8_B64"
test -n "$DIST_P12_B64" && test -n "$DIST_P12_PASSWORD" && test -n "$DIST_PROFILE_B64" && test -n "$DIST_WATCH_PROFILE_B64"
[[ "$ASC_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]
[[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]
work="$RUNNER_TEMP/testflight"
key_dir="$HOME/.appstoreconnect/private_keys"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$work" "$key_dir" "$profile_dir"
key_path="$key_dir/AuthKey_${ASC_KEY_ID}.p8"
keychain="$work/distribution.keychain-db"
profile_path=''
watch_profile_path=''
cleanup() {
  if [ -n "$profile_path" ]; then rm -f "$profile_path"; fi
  if [ -n "$watch_profile_path" ]; then rm -f "$watch_profile_path"; fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -f "$key_path"
  rm -rf "$work"
}
trap cleanup EXIT
printf '%s' "$ASC_API_KEY_P8_B64" | base64 -D > "$key_path"
unset ASC_API_KEY_P8_B64
export ASC_KEY_PATH="$key_path"
version="${RELEASE_TAG#testflight/}"
build="${version##*-b}"
version="${version%-b*}"
python3 -B "$tools/scripts/testflight_api.py" preflight --version "$version" --build "$build"
printf '%s' "$DIST_P12_B64" | base64 -D > "$work/distribution.p12"
printf '%s' "$DIST_PROFILE_B64" | base64 -D > "$work/distribution.mobileprovision"
printf '%s' "$DIST_WATCH_PROFILE_B64" | base64 -D > "$work/watch.mobileprovision"
unset DIST_P12_B64 DIST_PROFILE_B64 DIST_WATCH_PROFILE_B64
if [ ! -s "$work/distribution.p12" ] || [ ! -s "$work/distribution.mobileprovision" ] || [ ! -s "$work/watch.mobileprovision" ]; then
  echo 'FAIL: a signing secret decoded to an empty file' >&2
  exit 1
fi
echo 'PASS: signing secret files decoded into restricted temporary storage'
keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$keychain_password" "$keychain" >/dev/null
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/distribution.p12" -k "$keychain" -f pkcs12 \
  -P "$DIST_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$keychain_password" "$keychain" >/dev/null
unset DIST_P12_PASSWORD keychain_password
echo 'PASS: temporary signing identity imported'
security list-keychains -d user -s "$keychain"
python3 -B "$tools/scripts/testflight_signing.py" --role phone \
  --profile "$work/distribution.mobileprovision" --keychain "$keychain" --team "$ASC_TEAM_ID" \
  --output "$work/signing.json" --entitlements-output "$work/distribution-entitlements.plist"
python3 -B "$tools/scripts/testflight_signing.py" --role watch \
  --profile "$work/watch.mobileprovision" --keychain "$keychain" --team "$ASC_TEAM_ID" \
  --output "$work/watch-signing.json" --entitlements-output "$work/watch-entitlements.plist"
profile_uuid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' "$work/signing.json")"
watch_profile_uuid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' "$work/watch-signing.json")"
certificate_sha1="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["certificate_sha1"])' "$work/signing.json")"
watch_certificate_sha1="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["certificate_sha1"])' "$work/watch-signing.json")"
test "$certificate_sha1" = "$watch_certificate_sha1"
test "$profile_uuid" != "$watch_profile_uuid"
profile_path="$profile_dir/$profile_uuid.mobileprovision"
watch_profile_path="$profile_dir/$watch_profile_uuid.mobileprovision"
cp "$work/distribution.mobileprovision" "$profile_path"
cp "$work/watch.mobileprovision" "$watch_profile_path"
# Only Apple tools process the verified app; no candidate build scripts run here.
cp -R "$VERIFIED_ARCHIVE" "$work/PromptPace.xcarchive"
app="$work/PromptPace.xcarchive/Products/Applications/PacePrompt.app"
watch="$app/Watch/PacePromptWatch.app"
cp "$work/distribution.mobileprovision" "$app/embedded.mobileprovision"
cp "$work/watch.mobileprovision" "$watch/embedded.mobileprovision"
# Sign each nested bundle explicitly, enclosing app last.
codesign --force --sign "$certificate_sha1" --keychain "$keychain" \
  --entitlements "$work/watch-entitlements.plist" "$watch"
codesign --force --sign "$certificate_sha1" --keychain "$keychain" \
  --entitlements "$work/distribution-entitlements.plist" "$app"
python3 - "$work/PromptPace.xcarchive/Info.plist" "$ASC_TEAM_ID" <<'PYINFO'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    info = plistlib.load(source)
info['ApplicationProperties']['SigningIdentity'] = 'Apple Distribution'
info['ApplicationProperties']['Team'] = sys.argv[2]
with open(path, 'wb') as target:
    plistlib.dump(info, target)
PYINFO
echo 'PASS: verified unsigned archive signed without executing candidate build code'
cd "$work"
python3 - "$work/export-options.plist" "$ASC_TEAM_ID" "$profile_uuid" "$certificate_sha1" "$watch_profile_uuid" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'method': 'app-store-connect', 'destination': 'export',
        'signingStyle': 'manual', 'teamID': sys.argv[2],
        'provisioningProfiles': {'com.otherweather.PromptPace': sys.argv[3],
                                 'com.otherweather.PromptPace.watchkitapp': sys.argv[5]},
        'signingCertificate': sys.argv[4],
        'manageAppVersionAndBuildNumber': False,
        'testFlightInternalTestingOnly': True,
    }, output)
PY
xcodebuild -quiet -exportArchive -archivePath "$work/PromptPace.xcarchive" \
  -exportPath "$work/export" -exportOptionsPlist "$work/export-options.plist"
echo 'PASS: internal-only App Store export created'
ipa="$work/export/PacePrompt.ipa"
test -f "$ipa"
python3 -B "$tools/scripts/testflight_guard.py" exported \
  --ipa "$ipa" --destination "$work/payload" \
  --tag "$RELEASE_TAG" --team "$ASC_TEAM_ID" \
  --certificate-sha1 "$certificate_sha1"
digest="$(shasum -a 256 "$ipa" | awk '{print $1}')"
printf 'Source SHA: %s\nTrusted tools SHA: %s\nTag: %s\nBundle: com.otherweather.PromptPace\nVersion/build: %s (%s)\nIPA SHA-256: %s\n' \
  "$RELEASE_SHA" "$RELEASE_TOOLS_SHA" "$RELEASE_TAG" "$version" "$build" "$digest" >> "$GITHUB_STEP_SUMMARY"
# One upload attempt. A failure is ambiguous until App Store Connect is inspected.
xcrun altool --upload-app -f "$ipa" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
printf 'Upload command: accepted; awaiting Apple processing.\n' >> "$GITHUB_STEP_SUMMARY"
python3 -B "$tools/scripts/testflight_api.py" processed --version "$version" --build "$build"
printf 'Apple processing: valid. Existing internal group: assigned and observable.\n' >> "$GITHUB_STEP_SUMMARY"
