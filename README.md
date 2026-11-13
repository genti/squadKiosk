# squadMap Kiosk

Trasforma un telefono Android in un **totem dedicato a squadMap**: all'accensione si apre da solo
l'app squadMap, a schermo intero, e non si può uscire. Questo repo contiene tutto il necessario:
uno script che prepara il telefono e installa l'ultima versione di squadMap, e quello per ripristinarlo.

> **Disclaimer.** Software fornito "così com'è", senza garanzie. Lo script cambia in profondità il
> telefono (Device Owner, app di sistema disabilitate, schermo sempre acceso). Usalo solo su un telefono
> dedicato e senza dati personali. L'autore non risponde di blocchi, perdita di dati o danni.
> Lo script mostra lo stesso avviso e chiede di scrivere `ACCETTO` prima di toccare il telefono.

Testato su Huawei PRA-LX1 (Android 8.0). Funziona da Android 8.0 in su; la lista delle app da
disabilitare è pensata per Huawei (i pacchetti assenti vengono saltati).

## Requisiti

**PC (Linux/macOS)**: `bash`, `adb` (android-platform-tools), `curl`, `xz`.

**Telefono**
- Android 8.0 o superiore.
- *Opzioni sviluppatore* > *Debug USB* attivo e autorizzato; cavo USB in modalità "Trasferimento file".
- **Nessun account** configurato (Google, Huawei ID…): con un account Android rifiuta il Device Owner.
  Rimuovili da Impostazioni > Account prima di iniziare.

## Installazione

```bash
git clone https://github.com/genti/squadKiosk.git && cd squadKiosk
./kiosk.sh
```

Lo script, nell'ordine:

1. controlla PC e telefono (Android, account, Device Owner già presente);
2. mostra il disclaimer e chiede `ACCETTO`;
3. chiede il nome del totem (compare in *Info telefono* e nel nome Bluetooth);
4. disabilita le app non necessarie e imposta schermo intero e schermo sempre acceso in carica;
5. scarica `kiosk.apk` (il launcher) dalla Release, lo installa e lo imposta Device Owner;
6. scarica da questo repo (sezione *Releases*) l'ultima versione di squadMap, la scompatta e la installa.

Finito, il telefono è bloccato su squadMap e si riapre da solo a ogni accensione.
Con più telefoni collegati compare una lista numerata; oppure `ANDROID_SERIAL=<seriale>`.

## Comandi

| Comando | Cosa fa |
|---|---|
| `./kiosk.sh` | percorso guidato completo (configurazione + installazione squadMap) |
| `./kiosk.sh check` | verifica telefono e PC, **non modifica nulla** |
| `./kiosk.sh setup` | solo configurazione kiosk (rilanciabile quando vuoi) |
| `./kiosk.sh install-app` | installa o aggiorna squadMap all'ultima versione |
| `./kiosk.sh status` | Device Owner, Lock Task, app in primo piano, versione di squadMap, app disabilitate |
| `./kiosk.sh restore` | esce dal kiosk e riporta il telefono com'era (alias: `exit`) |

Opzioni:

| Variabile | Uso |
|---|---|
| `KIOSK_VERSION=vX.Y.Z` | installa una versione precisa di squadMap invece dell'ultima |
| `KIOSK_ACCEPT=yes` | salta disclaimer e conferme (`restore` disinstalla anche l'app Kiosk) |

## Aggiornare squadMap

```bash
./kiosk.sh install-app                          # ultima versione
KIOSK_VERSION=v1.2.0 ./kiosk.sh install-app     # una versione precisa
```

Il kiosk riapre l'app da solo. `./kiosk.sh status` mostra la versione installata.

## Cosa modifica la configurazione

- **App disabilitate** (`pm disable-user`): circa 70 pacchetti (Play Store, calendario, SMS, galleria,
  app Huawei…), elenco `DEBLOAT` in cima a `kiosk.sh`. Restano attivi Play Services, tastiera, fotocamera,
  WebView e telefonia. Quelle disattivate: `adb shell pm list packages -d`.
- **Schermo intero** per tutte le app: `settings put global policy_control immersive.full=*`.
- **Schermo sempre acceso in carica**: `stay_on_while_plugged_in 7` (valore originale salvato).
- **Device Owner** + Lock Task; barra di stato e blocco schermo disattivati.
- **Servizio di accessibilità** per l'uscita con i tasti volume.

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
**Vol+ Vol+ Vol- Vol- Vol+ Vol-**. Poi `./kiosk.sh restore` per riattivare anche le app.

**Rientrare nel kiosk**: `./kiosk.sh setup`. Dal solo telefono non è possibile: il Device Owner si imposta
solo via adb.

**Se `restore` non basta**

```bash
adb shell am start -n it.squadmap.kiosk/.KioskActivity --ez exit true
adb shell dpm remove-active-admin it.squadmap.kiosk/.AdminReceiver
adb shell settings delete global policy_control
adb shell pm enable <pacchetto>      # per ogni app disabilitata
```

Ultima risorsa: reset di fabbrica dalla recovery (Vol+ e accensione).

## Limiti noti

- In Lock Task le app non autorizzate non si aprono: i link esterni di squadMap (es. privacy policy) e le
  impostazioni di sistema restano bloccati.
- I permessi runtime (posizione, fotocamera) vanno concessi la prima volta dai dialog dell'app.
- Il Device Owner richiede un telefono senza account.

## Problemi comuni

| Messaggio / sintomo | Causa e rimedio |
|---|---|
| `nessun telefono su adb` | sblocca il telefono, abilita Debug USB e accetta la richiesta di autorizzazione |
| `ci sono N account sul telefono` | rimuovili da Impostazioni > Account, poi rilancia |
| `un'altra app è già Device Owner` | rimuovi quell'app o fai reset di fabbrica |
| `install launcher fallito` | launcher già installato con firma diversa: `./kiosk.sh restore`, poi `./kiosk.sh setup` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | squadMap già installata con un'altra firma: disinstallala dal telefono e rilancia `./kiosk.sh install-app` |
| `lock task non attivo` | rilancia `./kiosk.sh setup`; controlla con `./kiosk.sh status` |
| Schermata "Kiosk: non è Device Owner" | il kiosk è stato disattivato: `./kiosk.sh setup` |
| `download fallito` | controlla la connessione e che il repo abbia almeno una Release con `squadmap.apk.xz` e `kiosk.apk` |

## Contenuto del repo

```
kiosk.sh    script unico (check, setup, install-app, status, restore)
README.md   questa guida
```

Le app (`kiosk.apk` e `squadmap.apk.xz`) stanno nelle *Releases* e vengono scaricate dallo script.
