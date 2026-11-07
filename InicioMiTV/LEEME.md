# Inicio — Xiaomi Mi TV (Android TV)

Copia de `../InicioTV` (JVC) adaptada al TV Xiaomi **MiTV-M00Q2** (Android TV 11,
MediaTek), en 192.168.5.159. Mismo diseño estilo Apple TV; sólo cambian la lista de
apps ocultas y la fila de TV.

Diferencias con el JVC:
- `applicationId` = `local.fran.iniciomitv` (para no chocar con el del JVC).
- `HIDDEN` esconde la basura de Xiaomi/Google (Mi TV+, Galería, Alexa, explorador,
  smartshare, tvmanager, BrowseHere, launcher de Google) y **mantiene maxplayer**.
- Fila de TV: un solo **TV en vivo** = sintonizador `.../TunerInputService/HW0`
  (aquí el cable entra por coaxial), más **Entradas** y **Configuración**. No hay
  antena de aire ni cable por HDMI.

## Compilar, instalar y dejar de inicio
```
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH
adb connect 192.168.5.159:5555
./gradlew assembleDebug
adb -s 192.168.5.159:5555 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s 192.168.5.159:5555 shell cmd package set-home-activity local.fran.iniciomitv/local.fran.iniciotv.HomeActivity
adb -s 192.168.5.159:5555 shell pm disable-user --user 0 com.google.android.tvlauncher
```
Para revertir el inicio: `pm enable com.google.android.tvlauncher`.
En otro Android TV: ajustar `HIDDEN`/`FAVORITES` y el id de la entrada en HomeActivity.java
(ver `adb shell dumpsys tv_input`).
