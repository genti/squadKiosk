#!/usr/bin/env bash
# Builds kiosk.apk with the bare Android build-tools (no Gradle).
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)
JAR=$SDK/platforms/$(ls "$SDK/platforms" | sort -V | tail -1)/android.jar
# Throwaway signing key, generated once in build/ (gitignored) with a random password.
# A launcher built on another machine has another signature: run `./kiosk.sh restore` before swapping it.
KS=.kiosk-build.keystore
KSPASS_FILE=.kiosk-build.pass

rm -rf build && mkdir -p build/classes
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o build/unsigned.apk build/res.zip --java build/gen
javac -source 11 -target 11 -nowarn -classpath "$JAR" -d build/classes $(find src build/gen -name '*.java')
"$BT/d8" --min-api 26 --lib "$JAR" --output build $(find build/classes -name '*.class')
(cd build && zip -q unsigned.apk classes.dex)
"$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk
if [ ! -f "$KS" ]; then
  (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$KSPASS_FILE")
  keytool -genkeypair -keystore "$KS" -storepass:file "$KSPASS_FILE" -keypass:file "$KSPASS_FILE" \
    -alias kiosk -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=squadMap Kiosk" 2>/dev/null
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass "file:$KSPASS_FILE" --out kiosk.apk build/aligned.apk
echo "OK: $(pwd)/kiosk.apk"
