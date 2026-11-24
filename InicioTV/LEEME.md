# Inicio (pantalla de inicio para el JVC Google TV)

Pantalla de inicio minimalista al estilo Apple TV: hora y fecha, una cuadrícula fija de 5 columnas con las apps
y botones de TV en vivo, Entradas y Configuración abajo.

- Televisor: JVC 4K ISDB TV (Google TV, Android 11), IP 192.168.5.236, adb por red en el puerto 5555.
- Compilar e instalar:
  ./gradlew assembleDebug && adb -s 192.168.5.236:5555 install -r app/build/outputs/apk/debug/app-debug.apk
- Qué va en cada casilla: la tabla `LAYOUT` en HomeActivity.java (fila por fila, 5 columnas; las apps que no
  están ahí no se muestran). La selección arranca en `FOCUS_ROW`/`FOCUS_COL` («TV en vivo»).
- Entradas: antena `HW0`, cable en HDMI 2 (`HW5`), cajita Apple TV en HDMI 1 (`HW4`).
- «Apagar TV» usa un administrador del dispositivo (`PowerAdmin`). Se activó una vez con
  `adb shell dpm set-active-admin --user 0 local.fran.iniciotv/.PowerAdmin`; si no, el TV pide permiso la primera vez.

## Para instalarlo en otro televisor Google TV

1. En el televisor: Configuración → Sistema → Información → pulsar 7 veces «Compilación del SO de Android TV».
   Luego Sistema → Opciones de desarrollador → activar «Depuración por USB» (y «Depuración inalámbrica» si aparece).
2. Anotar la IP del televisor (Configuración → Red e Internet → la red Wi-Fi).
3. Desde el Mac: `adb connect IP:5555` y aceptar «Permitir siempre» en el televisor.
4. Revisar en ese televisor qué paquetes cambian (TV en vivo y apps que se quieran ocultar):
   `adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER`
   y ajustar `LAYOUT`, `ANTENNA`, `CABLE` y `APPLE_TV_INPUT` en HomeActivity.java si hace falta
   (los ids de las entradas salen con `adb shell dumpsys tv_input`).
5. Compilar e instalar (`./gradlew assembleDebug` y `adb install -r ...`).
6. Hacerlo la pantalla de inicio:
       adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
       adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
       adb shell cmd package set-home-activity local.fran.iniciotv/.HomeActivity
   Al desactivar el segundo, el televisor puede desaparecer de la red un par de minutos.

## Para volver a la pantalla de Google TV

    adb connect 192.168.5.236:5555
    adb shell pm enable com.google.android.tungsten.setupwraith
    adb shell pm enable com.google.android.apps.tv.launcherx

## Al encender, abrir el inicio
Configuración → Sistema → Encendido y energía → «Comportamiento cuando se enciende la TV».
Ese panel lo dibuja el inicio de Google: con él desactivado sale vacío. Para cambiarlo,
`pm enable com.google.android.apps.tv.launcherx`, elegir «Pantalla principal», volver a
desactivarlo y repetir `cmd package set-home-activity local.fran.iniciotv/.HomeActivity`.
