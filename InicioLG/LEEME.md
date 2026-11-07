# Inicio — LG (webOS)

Pantalla de inicio estilo Apple TV para el TV LG de la casa (55NANO79SNA, webOS 5.6),
hermana de `../InicioTV` (que es para Google TV). Es una app web de webOS.

## Qué hace
- Grilla de 5 columnas con las apps del TV (banners) y, al final, los accesos del TV:
  **TV en vivo** (sintonizador, por donde entra el cable coaxial), **Entradas** (Panel del
  hogar de LG) y **Configuración**.
- Hora y fecha arriba a la derecha, fondo difuminado del cuadro seleccionado.
- La lista de apps es fija en `index.html` (`APPS`), porque webOS no deja que una app
  normal lea las apps instaladas (sí se pueden listar por la API de control remoto desde
  fuera, que es como se sacaron los ids e íconos).

## Cómo conectarse al TV (desde el Mac)
El TV tiene que estar en **Modo desarrollador** (app Developer Mode de LG, con Key Server
encendido). Herramientas: `@webos-tools/cli` (npm). Registro una sola vez:

```
ares-setup-device -a lgsala -i "host=<IP>" -i "port=9922" -i "username=prisoner" -i "default=true"
ares-novacom --device lgsala --getkey   # pide la passphrase que muestra la app del TV
```

## Compilar e instalar
```
ares-package InicioLG -o /tmp/ipk
ares-launch -d lgsala --close local.fran.inicio   # cerrarla antes, si no el install falla
ares-install -d lgsala /tmp/ipk/local.fran.inicio_<version>_all.ipk
ares-launch -d lgsala local.fran.inicio
```
Subir el número de `version` en `appinfo.json` en cada reinstalación.

## El botón Home
En LG el botón Home **no se puede reprogramar** sin root (y ni con root queda limpio en
webOS 5). Para abrir «Inicio» a un clic: asignarla a una **tecla de número** del control
(mantener apretado el número con la app abierta → registrar), o ponerla de primera en la
barra de LG (Home → mantener OK sobre la app → mover al inicio).

## Entradas de este TV
El cable entra por **coaxial** → sintonizador (`com.webos.app.livetv`), no por HDMI.
Las entradas del TV se consultan con la API de control remoto (`ssap://tv/getExternalInputList`).
En otro LG, revisar los ids de `SYSTEM` en `index.html` y las apps de `APPS`.
