#!/bin/sh
# Re-signs simulator builds with your team's Apple Development certificate.
#
# Why: Xcode signs simulator apps "to run locally", with no team. On iOS 26 the
# system's App Intents service refuses intents from an app with no team, so the
# alarm's Taken button and "slide to stop" do nothing in the simulator.
# Builds for a real iPhone are already signed with the team and skip this.
#
# The PillBox scheme runs this after every build (Build post-action).

[ "$PLATFORM_NAME" = "iphonesimulator" ] || exit 0

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
[ -d "$APP" ] || { echo "sign-simulator-build: no app at $APP"; exit 0; }

# Pick the Apple Development certificate for this project's team (DEVELOPMENT_TEAM).
IDENTITY=""
for HASH in $(security find-identity -v -p codesigning | grep "Apple Development" | awk '{print $2}'); do
  SUBJECT=$(security find-certificate -a -Z -p -c "Apple Development" 2>/dev/null \
    | awk -v h="$HASH" '/^SHA-1 hash:/{keep=($3==h)} keep' \
    | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' \
    | openssl x509 -noout -subject 2>/dev/null)
  case "$SUBJECT" in
    *"$DEVELOPMENT_TEAM"*) IDENTITY="$HASH"; break ;;
  esac
done

if [ -z "$IDENTITY" ]; then
  echo "sign-simulator-build: no Apple Development certificate for team $DEVELOPMENT_TEAM; alarm buttons won't work in the simulator."
  exit 0
fi

for LIB in "$APP"/*.dylib; do
  [ -f "$LIB" ] && codesign --force --sign "$IDENTITY" --timestamp=none "$LIB"
done
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "sign-simulator-build: signed $WRAPPER_NAME for team $DEVELOPMENT_TEAM"
