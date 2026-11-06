#!/bin/zsh
# Builds, signs, notarizes and staples dist/LahLahVoice.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
ID="Developer ID Application: Alfred Ang (GU9WTSTX9M)"
set -a; source ./.env; set +a
KEY=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

xcodebuild -project NovaVoice.xcodeproj -scheme NovaVoiceMac -configuration Release \
  -derivedDataPath build/ddr OTHER_CODE_SIGN_FLAGS="--timestamp" build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' || true

APP="build/ddr/Build/Products/Release/LahLah Voice.app"
# Notarization needs a secure timestamp and no debug entitlements on every signed item.
codesign --force --options runtime --timestamp --entitlements Apps/macOS/NovaVoice.entitlements --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "LahLah Voice" -srcfolder "$STAGE" -ov -format UDZO dist/LahLahVoice.dmg >/dev/null
codesign --force --sign "$ID" --timestamp dist/LahLahVoice.dmg

xcrun notarytool submit dist/LahLahVoice.dmg "${KEY[@]}" --wait
xcrun stapler staple dist/LahLahVoice.dmg
spctl -a -vv -t open --context context:primary-signature dist/LahLahVoice.dmg
