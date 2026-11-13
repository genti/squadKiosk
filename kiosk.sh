#!/usr/bin/env bash
# squadMap totem: turn an Android phone into a single-app kiosk running squadMap.
#
#   ./kiosk.sh                  guided: checks, disclaimer, setup, install squadMap
#   ./kiosk.sh check            verify phone and PC only (changes nothing)
#   ./kiosk.sh setup            debloat, fullscreen, kiosk launcher as Device Owner
#   ./kiosk.sh install-app [f]  install squadMap from f (.apk, .apk.xz or .aab); default: GitHub Release (latest, or KIOSK_VERSION=vX.Y.Z)
#   ./kiosk.sh status           show kiosk state of the phone
#   ./kiosk.sh restore          leave kiosk and undo what setup changed (alias: exit)
#
# Several phones on adb: a numbered list is shown (or set ANDROID_SERIAL).
# Env: KIOSK_REPO=user/repo (Release source), KIOSK_VERSION=vX.Y.Z (default: latest),
#      KIOSK_ACCEPT=yes (skip prompts),
#      .aab only, optional signing: KS_FILE KS_PASS KS_ALIAS (else bundletool debug key).
set -euo pipefail
cd "$(dirname "$0")"

KIOSK=it.squadmap.kiosk
ADMIN=$KIOSK/.AdminReceiver
EXIT_SERVICE=$KIOSK/$KIOSK.ExitService
TARGET=it.davidegentilucci.squadmap
REPO=${KIOSK_REPO:-genti/squadKiosk}   # GitHub "user/repo" hosting the Releases
BUNDLETOOL_VERSION=1.18.1
BUNDLETOOL=tools/bundletool-all-$BUNDLETOOL_VERSION.jar
STATE_DIR=.kiosk-state

# Not needed on a totem. Play Services, WebView, SwiftKey, camera and telephony stay enabled.
# Meant for the Huawei PRA-LX1; packages missing on other phones are skipped.
DEBLOAT=(
  com.android.calendar com.android.contacts com.android.deskclock com.android.mms
  com.android.mediacenter com.android.gallery3d com.android.dreams.basic
  com.android.dreams.phototable com.android.egg com.android.bips com.android.printspooler
  com.hp.android.printservice com.google.android.printservice.recommendation
  com.android.wallpaper.livepicker com.android.bookmarkprovider
  com.android.partnerbrowsercustomizations.tmobile com.facebook.system
  com.google.android.feedback com.google.android.marvin.talkback
  com.google.android.syncadapters.calendar com.google.android.syncadapters.contacts
  com.android.vending com.huawei.android.hwouc com.huawei.android.hwupgradeguide
  com.huawei.appmarket com.huawei.android.thememanager com.huawei.android.totemweather
  com.huawei.android.totemweatherwidget com.huawei.tips com.huawei.vassistant
  com.huawei.videoeditor com.huawei.himovie.overseas com.huawei.hicloud com.huawei.hidisk
  com.huawei.android.instantshare com.huawei.android.mirrorshare com.huawei.android.FloatTasks
  com.huawei.screenrecorder com.huawei.HwMultiScreenShot com.huawei.watch.sync
  com.huawei.iconnect com.huawei.nearby com.huawei.synergy com.huawei.intelligent
  com.huawei.hiaction com.huawei.recsys com.huawei.bd com.huawei.android.instantonline
  com.huawei.android.wfdft com.huawei.hwid com.huawei.motionservice com.huawei.android.pushagent
  com.google.android.youtube com.google.android.googlequicksearchbox com.huawei.phoneservice
  com.google.android.apps.work.oobconfig com.google.android.gm com.google.android.apps.tachyon
  com.google.android.music com.google.android.apps.docs com.google.android.apps.maps
  com.example.android.notepad com.android.chrome com.google.android.videos
  com.google.android.apps.photos com.android.calculator2 com.huawei.android.totemweatherapp
  com.android.email com.huawei.scanner com.facebook.appmanager
)

say() { printf '\n== %s\n' "$*"; }
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }
sh_() { adb shell "$@" </dev/null | tr -d '\r'; }
yes_() { [ "${KIOSK_ACCEPT:-}" = yes ] || { local a; read -rp "$1 [s/N] " a; [[ $a =~ ^[sSyY] ]]; }; }

# Shows connected devices (serial, model, totem name) and exports the chosen ANDROID_SERIAL.
need_device() {
  command -v adb >/dev/null || die "adb non trovato (installa android-platform-tools)"
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    [ "$(adb get-state 2>/dev/null)" = device ] || die "$ANDROID_SERIAL non raggiungibile su adb"
    return
  fi
  local serials=() labels=() s
  while read -r s; do
    serials+=("$s")
    labels+=("$s  $(adb -s "$s" shell getprop ro.product.model </dev/null | tr -d '\r')  \"$(adb -s "$s" shell settings get global device_name </dev/null | tr -d '\r')\"")
  done < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  [ ${#serials[@]} -gt 0 ] || die "nessun telefono su adb (sblocca, USB 'Trasferimento file', autorizza il debug)"
  if [ ${#serials[@]} -eq 1 ]; then
    export ANDROID_SERIAL=${serials[0]}
    return
  fi
  say "Dispositivi collegati"
  local PS3="Numero del dispositivo: "
  select s in "${labels[@]}"; do
    [ -n "$s" ] && break
  done
  export ANDROID_SERIAL=${serials[$((REPLY - 1))]}
}

# Totem name shown in the device list, Settings > About and Bluetooth.
name_device() {
  local cur name; cur=$(sh_ settings get global device_name)
  [ "$cur" != null ] || cur=$(sh_ getprop ro.product.model)
  if [ "${KIOSK_ACCEPT:-}" = yes ]; then return; fi
  read -rp "Nome del totem [$cur]: " name
  name=${name:-$cur}
  [ "$name" = "$cur" ] && return
  sh_ settings put global device_name "\"$name\""
  sh_ settings put secure bluetooth_name "\"$name\""
  echo "  nome: $(sh_ settings get global device_name)"
}

is_owner() { sh_ dumpsys device_policy | grep -q "admin=ComponentInfo{$KIOSK/"; }
state_file() { echo "$STATE_DIR/$ANDROID_SERIAL"; }

# Phone + PC sanity checks. Dies on blockers, changes nothing.
cmd_check() {
  need_device
  local model ver sdk accounts
  model=$(sh_ getprop ro.product.model); ver=$(sh_ getprop ro.build.version.release)
  sdk=$(sh_ getprop ro.build.version.sdk)
  say "Telefono: $model, Android $ver (SDK $sdk), serial $ANDROID_SERIAL"
  [ "$sdk" -ge 26 ] || die "serve Android 8.0 o superiore"
  if is_owner; then
    echo "  Device Owner: già il kiosk"
  else
    sh_ dumpsys device_policy | grep -q 'Device Owner' && die "un'altra app è già Device Owner: rimuovila o fai reset di fabbrica"
    accounts=$(sh_ dumpsys account | grep -cE '^\s+Account \{' || true)
    [ "$accounts" = 0 ] || die "ci sono $accounts account sul telefono: rimuovili (Impostazioni > Account) e rilancia"
  fi
  if sh_ pm list packages | grep -q "package:$TARGET"; then echo "  squadMap: installata"; else echo "  squadMap: non installata"; fi
  [ "$(sh_ getprop ro.product.brand | tr 'A-Z' 'a-z')" = huawei ] \
    || echo "  ATTENZIONE: non è un Huawei, la lista di app da disabilitare è pensata per PRA-LX1"
  command -v java >/dev/null || echo "  nota: java assente (serve solo per installare da .aab)"
  echo "  OK: controlli superati"
}

disclaimer() {
  [ "${KIOSK_ACCEPT:-}" = yes ] && return
  cat <<'TXT'

================================ DISCLAIMER ================================
Questo script trasforma il telefono in un totem che esegue SOLO squadMap.

  - imposta l'app Kiosk come Device Owner e blocca il telefono (Lock Task);
  - disabilita circa 70 app di sistema (Play Store, galleria, SMS, app Huawei...);
  - disattiva barra di stato e blocco schermo, schermo sempre acceso in carica;
  - attiva un servizio di accessibilità per l'uscita con la sequenza dei tasti volume.

Usalo solo su un telefono dedicato, senza dati personali. Software fornito
"così com'è", senza garanzie: l'autore non risponde di blocchi, perdita di dati
o danni. Se qualcosa va storto: ./kiosk.sh restore, oppure la sequenza volume
(Vol+ Vol+ Vol- Vol- Vol+ Vol-), oppure reset di fabbrica dalla recovery.
============================================================================
TXT
  local a; read -rp "Scrivi ACCETTO per continuare: " a
  [ "$a" = ACCETTO ] || die "non accettato, nessuna modifica fatta"
}

# Release asset URL: latest, or a pinned tag via KIOSK_VERSION.
release_url() {
  if [ -n "${KIOSK_VERSION:-}" ]; then echo "https://github.com/$REPO/releases/download/$KIOSK_VERSION/$1"
  else echo "https://github.com/$REPO/releases/latest/download/$1"; fi
}

app_version() { sh_ dumpsys package "$TARGET" | sed -n 's/^ *versionName=//p' | head -1; }

# Launcher APK: downloaded from the Release (kiosk.apk), or a local kiosk.apk next to this script.
get_launcher() {
  [ -f kiosk.apk ] && return
  curl -fL -o kiosk.apk "$(release_url kiosk.apk)" \
    || die "download di kiosk.apk fallito (la release deve contenere kiosk.apk)"
}

cmd_setup() {
  cmd_check
  disclaimer
  name_device
  mkdir -p "$STATE_DIR"
  local st p; st=$(state_file)
  [ -f "$st" ] || echo "stay_on=$(sh_ settings get global stay_on_while_plugged_in)" > "$st"

  say "Disabilito app non necessarie"
  local installed; installed=$(sh_ pm list packages -e | sed 's/package://')
  for p in "${DEBLOAT[@]}"; do
    grep -qx "$p" <<<"$installed" || continue
    if sh_ pm disable-user --user 0 "$p" | grep -q disabled-user; then
      echo "  off $p"
      grep -qx "disabled=$p" "$st" || echo "disabled=$p" >> "$st"
    else
      echo "  ?? $p"
    fi
  done

  say "Schermo sempre acceso in carica, app a schermo intero"
  sh_ settings put global stay_on_while_plugged_in 7
  sh_ settings put global policy_control 'immersive.full=*'

  say "Installo il launcher kiosk"
  get_launcher
  adb install -r -t kiosk.apk >/dev/null \
    || die "install launcher fallito (firma diversa da quella installata? lancia prima: $0 restore)"

  say "Device Owner"
  if is_owner; then echo "  già Device Owner"; else sh_ dpm set-device-owner "$ADMIN"; fi

  say "Uscita con tasti volume (servizio accessibilità)"
  sh_ settings put secure enabled_accessibility_services "$EXIT_SERVICE"
  sh_ settings put secure accessibility_enabled 1

  say "Avvio kiosk"
  sh_ am start -n "$KIOSK/.KioskActivity" >/dev/null
  sleep 3
  if sh_ dumpsys activity activities | grep -q 'mLockTaskModeState=LOCKED'; then
    echo "  OK: telefono bloccato in kiosk"
  else
    die "lock task non attivo"
  fi
}

bundletool() {
  command -v java >/dev/null || die "java necessario per installare da .aab"
  if [ ! -f "$BUNDLETOOL" ]; then
    say "Scarico bundletool $BUNDLETOOL_VERSION"
    mkdir -p tools
    curl -fL -o "$BUNDLETOOL" \
      "https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
  fi
  java -jar "$BUNDLETOOL" "$@"
}

cmd_install_app() {
  local src=${1:-} tmp; tmp=$(mktemp -d)
  trap 'rm -rf "${tmp:-}"; trap - RETURN' RETURN
  if [ -z "$src" ]; then
    [ -n "$REPO" ] || die "indica un file (.apk/.apk.xz/.aab) oppure imposta KIOSK_REPO=utente/repo"
    local ver=${KIOSK_VERSION:-}
    say "Scarico squadMap ${ver:-(ultima release)} da $REPO"
    curl -fL -o "$tmp/squadmap.apk.xz" "$(release_url squadmap.apk.xz)" \
      || die "download fallito (la release deve contenere squadmap.apk.xz)"
    src=$tmp/squadmap.apk.xz
  fi
  [ -f "$src" ] || die "file non trovato: $src"
  need_device
  if [[ $src == *.xz ]]; then
    command -v xz >/dev/null || die "xz necessario per scompattare $src"
    say "Scompatto $src"
    xz -dc "$src" > "$tmp/app.apk"
    src=$tmp/app.apk
  fi
  if [[ $src == *.aab ]]; then
    say "AAB -> APK universale"
    local sign=()
    if [ -n "${KS_FILE:-}" ]; then
      sign=(--ks="$KS_FILE" --ks-key-alias="${KS_ALIAS:-key}" --ks-pass="pass:${KS_PASS:?KS_PASS mancante}")
    fi
    bundletool build-apks --bundle="$src" --output="$tmp/app.apks" --mode=universal --overwrite "${sign[@]}"
    unzip -q -o "$tmp/app.apks" universal.apk -d "$tmp"
    src=$tmp/universal.apk
  fi
  say "Installo squadMap (installata: $(app_version))"
  adb install -r "$src" || die "install fallito. Con INSTALL_FAILED_UPDATE_INCOMPATIBLE la firma è cambiata: adb uninstall $TARGET e riprova"
  sleep 4
  echo "  versione installata: $(app_version)"
  sh_ dumpsys activity activities | grep -m1 mResumedActivity || true
}

cmd_status() {
  need_device
  say "Stato di $ANDROID_SERIAL"
  if is_owner; then echo "  Device Owner: sì (kiosk attivo)"; else echo "  Device Owner: no"; fi
  sh_ dumpsys activity activities | grep -m1 'mLockTaskModeState' | sed 's/^ */  /' || true
  sh_ dumpsys activity activities | grep -m1 mResumedActivity | sed 's/^ */  /' || true
  echo "  squadMap versione: $(app_version)"
  echo "  app disabilitate: $(sh_ pm list packages -d | wc -l)"
  echo "  policy_control: $(sh_ settings get global policy_control)"
}

cmd_restore() {
  need_device
  yes_ "Uscire dal kiosk e ripristinare il telefono?" || die "annullato"
  if is_owner; then
    say "Esco dal kiosk"
    sh_ am start -n "$KIOSK/.KioskActivity" --ez exit true >/dev/null 2>&1 || true
    sleep 2
    if is_owner; then die "ancora Device Owner (riserva: adb shell dpm remove-active-admin $ADMIN)"; fi
  fi

  say "Riattivo le app disabilitate"
  local st p list=() stay; st=$(state_file)
  if [ -f "$st" ]; then
    mapfile -t list < <(sed -n 's/^disabled=//p' "$st")
  else
    echo "  nessuno stato salvato: riattivo l'intera lista"; list=("${DEBLOAT[@]}")
  fi
  for p in "${list[@]}"; do
    if sh_ pm enable --user 0 "$p" >/dev/null 2>&1; then echo "  on  $p"; fi
  done

  say "Ripristino impostazioni"
  sh_ settings delete global policy_control >/dev/null
  stay=$(sed -n 's/^stay_on=//p' "$st" 2>/dev/null || true)
  if [ -z "$stay" ] || [ "$stay" = null ]; then
    sh_ settings delete global stay_on_while_plugged_in >/dev/null
  else
    sh_ settings put global stay_on_while_plugged_in "$stay"
  fi
  if [ "$(sh_ settings get secure enabled_accessibility_services)" = "$EXIT_SERVICE" ]; then
    sh_ settings delete secure enabled_accessibility_services >/dev/null
    sh_ settings put secure accessibility_enabled 0
  fi
  rm -f "$st"

  if sh_ pm list packages | grep -q "package:$KIOSK"; then
    if yes_ "Disinstallare anche l'app Kiosk?"; then
      sh_ pm uninstall "$KIOSK" >/dev/null && echo "  Kiosk disinstallato"
    fi
  fi
  sh_ input keyevent KEYCODE_HOME
  echo; echo "Ripristinato. Rientro nel kiosk: $0 setup"
}

cmd_guided() {
  cmd_setup
  cmd_install_app "${1:-}"
}

case "${1:-}" in
  check) cmd_check ;;
  setup) cmd_setup ;;
  install-app) shift; cmd_install_app "$@" ;;
  status) cmd_status ;;
  restore|exit) cmd_restore ;;
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) cmd_guided "$@" ;;
esac
