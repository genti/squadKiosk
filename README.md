# squadMap Kiosk (totem)

Trasforma un telefono Android in un **totem dedicato a squadMap**: all'accensione si apre da solo
l'app squadMap, a schermo intero, e non si può uscire. L'app squadMap non viene modificata.

Un unico script, `kiosk.sh`, fa tutto: verifica il telefono, mostra il disclaimer, disabilita le app
inutili, installa il launcher kiosk e squadMap, e può **ripristinare il telefono** com'era.

Testato su Huawei PRA-LX1 (Android 8.0). Funziona in teoria da Android 8.0 in su; la lista delle app da
disabilitare è pensata per Huawei (i pacchetti assenti vengono saltati).

> **Disclaimer.** Software fornito "così com'è", senza garanzie. Lo script cambia in profondità il
> telefono (Device Owner, app di sistema disabilitate, schermo sempre acceso). Usalo solo su un telefono
> dedicato e senza dati personali. L'autore non risponde di blocchi, perdita di dati o danni.
> Lo script mostra lo stesso avviso e chiede di scrivere `ACCETTO` prima di toccare il telefono.

## Come funziona

- Il launcher (l'app "Kiosk") è l'app **Home** predefinita ed è **Device Owner**.
- Con il Lock Task blocca il telefono su squadMap: niente Home, Recenti, barra di stato o blocco schermo.
- Ad ogni avvio, o se squadMap si chiude, il launcher la riapre.
- Un servizio di accessibilità ascolta i tasti volume per l'uscita di emergenza (vedi sotto).

## Requisiti

**PC (Linux/macOS)**: `bash`, `adb` (android-platform-tools), `curl`.
Opzionali: Android SDK con build-tools (per compilare il launcher da sorgente), `java` (solo per installare da `.aab`).

**Telefono**: Android 8.0+, *Opzioni sviluppatore* > *Debug USB* attivo e autorizzato, cavo USB in modalità
"Trasferimento file", **nessun account** configurato (Google, Huawei ID…): senza, Android rifiuta il Device Owner.
Gli account vanno rimossi prima del setup.

## Avvio rapido

```bash
git clone https://github.com/CHANGE_ME/squadmap-kiosk.git && cd squadmap-kiosk
export KIOSK_REPO=CHANGE_ME/squadmap-kiosk   # oppure modifica REPO in kiosk.sh
./kiosk.sh
```

Lo script, nell'ordine:

1. controlla PC e telefono (Android, account, Device Owner già presente, squadMap installata);
2. mostra il disclaimer e chiede `ACCETTO`;
3. chiede il nome del totem (finisce in *Info telefono* e nel nome Bluetooth);
4. disabilita le app non necessarie e imposta schermo intero e schermo sempre acceso in carica;
5. installa il launcher e lo imposta Device Owner;
6. scarica l'ultima Release di squadMap (`squadmap.apk`) e la installa. Il kiosk la apre da solo.

## Comandi

| Comando | Cosa fa |
|---|---|
| `./kiosk.sh` | percorso guidato completo (setup + installazione squadMap) |
| `./kiosk.sh check` | verifica telefono e PC, **non modifica nulla** |
| `./kiosk.sh setup` | solo configurazione kiosk (rilanciabile quando vuoi) |
| `./kiosk.sh install-app [file]` | installa/aggiorna squadMap da `.apk`, `.aab` o, senza argomenti, dall'ultima Release |
| `./kiosk.sh status` | Device Owner, Lock Task, app in primo piano, app disabilitate |
| `./kiosk.sh restore` | esce dal kiosk e annulla le modifiche (alias: `exit`) |

Con più telefoni collegati compare una lista numerata (seriale, modello, nome); oppure `ANDROID_SERIAL=<seriale>`.

Variabili d'ambiente:

| Variabile | Uso |
|---|---|
| `KIOSK_REPO=utente/repo` | repo GitHub da cui scaricare `squadmap.apk` e `kiosk.apk` dalle Release |
| `KIOSK_ACCEPT=yes` | salta disclaimer e conferme (automazioni; `restore` disinstalla anche il Kiosk) |
| `KS_FILE`, `KS_PASS`, `KS_ALIAS` | solo per `.aab`: keystore con cui firmare l'APK (altrimenti chiave debug di bundletool) |

## Cosa modifica il setup

- **App disabilitate** (`pm disable-user`): circa 70 pacchetti (Play Store, calendario, SMS, galleria,
  app Huawei…), elenco `DEBLOAT` in cima a `kiosk.sh`. Restano attivi Play Services, tastiera, fotocamera,
  WebView e telefonia. Vedi quelle disattivate con `adb shell pm list packages -d`.
- **Schermo intero** per tutte le app: `settings put global policy_control immersive.full=*`.
- **Schermo sempre acceso in carica**: `stay_on_while_plugged_in 7` (valore originale salvato).
- **Device Owner** + Lock Task, barra di stato e blocco schermo disattivati.
- **Servizio di accessibilità** `ExitService` per l'uscita con i volume.

Le app realmente disabilitate e il valore originale dello schermo acceso sono salvati in
`.kiosk-state/<seriale>` sul PC, per il ripristino. Non cancellare quella cartella finché il totem è attivo.

## Uscire e ripristinare

**Dal PC (consigliato)**

```bash
./kiosk.sh restore
```

Esce dal kiosk, toglie Device Owner, Home predefinita e servizio di accessibilità, riattiva le app disabilitate,
rimuove schermo intero forzato e schermo sempre acceso, e (se confermi) disinstalla l'app Kiosk.
Funziona anche se eri già uscito con i volumi.

**Dal telefono, anche con squadMap aperta**: premi entro 5 secondi
**Vol+ Vol+ Vol- Vol- Vol+ Vol-** (sequenza e timeout in `ExitService.java`). Poi `./kiosk.sh restore`
per riattivare anche le app.

**Rientrare nel kiosk**: `./kiosk.sh setup`. Dal solo telefono non è possibile (Device Owner si imposta solo
via adb o con provisioning al primo avvio).

**Se `restore` non basta**

```bash
adb shell am start -n it.squadmap.kiosk/.KioskActivity --ez exit true
adb shell dpm remove-active-admin it.squadmap.kiosk/.AdminReceiver   # l'APK è testOnly
adb shell settings delete global policy_control
adb shell pm enable <pacchetto>                                      # per ogni app disabilitata
```

Ultima risorsa: reset di fabbrica dalla recovery (Vol+ e accensione).

## Aggiornare

- **squadMap**: `./kiosk.sh install-app` (ultima Release) o `./kiosk.sh install-app app.apk`. Il kiosk riapre l'app.
- **Launcher**: `./build.sh && adb install -r -t kiosk.apk`. Un launcher compilato su un'altra macchina ha
  un'altra firma e Android rifiuta l'aggiornamento: in quel caso `./kiosk.sh restore` (disinstalla il Kiosk) e poi `./kiosk.sh setup`.

## Per chi pubblica le Release

L'APK di squadMap si ricava dall'AAB e si firma **una volta, in locale**, con la tua chiave privata;
va nella Release **solo l'APK**. Un APK universale funziona su tutti i telefoni Android 8+ e gli utenti non
hanno bisogno né di chiavi né di bundletool. Tutte le Release future devono usare la stessa chiave, altrimenti
Android rifiuta l'aggiornamento.

```bash
java -jar bundletool-all-1.18.1.jar build-apks --bundle=app.aab --output=app.apks --mode=universal \
  --ks=/percorso/chiave.jks --ks-key-alias=ALIAS          # chiede le password
unzip -o app.apks universal.apk && mv universal.apk squadmap.apk
gh release create vX.Y.Z squadmap.apk [kiosk.apk] --title "squadMap vX.Y.Z"
```

Nomi file attesi dallo script: `squadmap.apk` e (opzionale) `kiosk.apk`. Non committare mai chiavi, `.aab`
o `.apk`: `.gitignore` li esclude già (`*.jks`, `*.keystore`, `*.aab`, `*.apk`, `build/`, `.kiosk-state/`).

`build.sh` firma il launcher con una chiave casuale creata al primo uso in `.kiosk-build.keystore`
(password in `.kiosk-build.pass`, entrambi ignorati da git). Per distribuire un `kiosk.apk` nella Release
firmato in modo stabile, compilalo una volta e riusa sempre quel file.

## Limiti noti

- In Lock Task le app non autorizzate non si aprono: link esterni di squadMap (`Linking.openURL`, es. privacy
  policy) e impostazioni di sistema restano bloccati.
- I permessi runtime (posizione, fotocamera) vanno concessi la prima volta dai dialog dell'app.
- Il Device Owner richiede un telefono senza account.

## Problemi comuni

| Messaggio / sintomo | Causa e rimedio |
|---|---|
| `nessun telefono su adb` | sblocca il telefono, abilita Debug USB e accetta la richiesta di autorizzazione |
| `ci sono N account sul telefono` | rimuovili da Impostazioni > Account, poi rilancia |
| `un'altra app è già Device Owner` | rimuovi quell'app o fai reset di fabbrica |
| `install launcher fallito` | firma diversa dal Kiosk installato: `./kiosk.sh restore`, poi `./kiosk.sh setup` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | squadMap firmata con un'altra chiave: disinstalla squadMap dal telefono e reinstalla |
| `lock task non attivo` | rilancia `./kiosk.sh setup`; controlla con `./kiosk.sh status` |
| Schermata "Kiosk: non è Device Owner" | il kiosk è stato disattivato: `./kiosk.sh setup` |
| `download fallito` | imposta `KIOSK_REPO` e verifica che la Release contenga `squadmap.apk` |

## Struttura del repo

```
kiosk.sh            script unico (check, setup, install-app, status, restore)
build.sh            compila e firma il launcher con le sole build-tools Android
AndroidManifest.xml, res/, src/   sorgente del launcher (KioskActivity, AdminReceiver, ExitService)
```
