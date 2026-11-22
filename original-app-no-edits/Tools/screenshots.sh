#!/bin/zsh
# Saves a screenshot of every iPhone screen into design/screens for Figma.
# Usage: Tools/screenshots.sh <simulator-udid>   (app must already be installed with demo data loaded)
U=${1:?simulator udid}
OUT=design/screens
mkdir -p $OUT
xcrun simctl status_bar $U override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1
i=1
for screen in today pillbox meds med prescriber message alerts scan review take snooze settings empty; do
  xcrun simctl terminate $U com.emmagelman.PillBox >/dev/null 2>&1
  if [[ $screen == empty ]]; then
    xcrun simctl launch $U com.emmagelman.PillBox -inMemory -screen empty >/dev/null
  else
    xcrun simctl launch $U com.emmagelman.PillBox -screen $screen >/dev/null
  fi
  sleep 4
  [[ $screen == review ]] && sleep 3
  xcrun simctl io $U screenshot "$OUT/$(printf %02d $i)-$screen.png" >/dev/null 2>&1
  echo "saved $(printf %02d $i)-$screen.png"
  i=$((i+1))
done
xcrun simctl status_bar $U clear >/dev/null 2>&1
xcrun simctl terminate $U com.emmagelman.PillBox >/dev/null 2>&1
