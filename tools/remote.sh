#!/bin/bash
# Run a command on the USB host the tablet is attached to.
# Usage: remote.sh adb shell getprop | remote.sh fastboot getvar all
set -euo pipefail
. "$(dirname "$0")/env"
printf -v cmd '%q ' "$@"
# Use USB when the tablet enumerates there, otherwise the Wi-Fi relay
# (see adb-wifi-relay.sh on the USB host).
exec ssh -i "$DIZI_SSH_KEY" -o BatchMode=yes "$DIZI_HOST" \
	"export PATH=/opt/homebrew/bin:\$PATH
	 if [ $1 != adb ] || adb devices | grep -q '^$DIZI_SERIAL'; then export ANDROID_SERIAL=$DIZI_SERIAL
	 else adb connect $DIZI_WIFI >/dev/null 2>&1; export ANDROID_SERIAL=$DIZI_WIFI; fi
	 $cmd"
