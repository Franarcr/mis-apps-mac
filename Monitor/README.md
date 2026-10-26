# Monitor

Widget flotante para macOS (14+) que muestra en tiempo real (cada segundo) los recursos del Mac:

- **CPU**, **memoria** y **GPU**, con la gráfica de los últimos 60 segundos
- **Temperatura** del chip (el sensor más caliente) y el estado térmico de macOS. Si macOS empieza a frenar el procesador para enfriarse, se marca en rojo
- **Consumo** total del Mac en vatios, según la batería (en Mac de sobremesa no aparece)
- **Red**: bajada (↓ cian) y subida (↑ rosa), y debajo la conexión: nombre de la red Wi-Fi, banda (2,4, 5 o 6 GHz), estándar (Wi-Fi 4 a 7) y calidad de la señal, o «Por cable»
- La primera vez pide permiso de **ubicación**: macOS solo deja ver el nombre de la red Wi-Fi a las apps que lo tienen. Monitor no usa ni guarda la ubicación
- **Disco**: lectura (L naranja), escritura (E amarillo) y espacio libre
- **Batería**: porcentaje y estado de carga
- Los **3 procesos que más CPU usan**

Un segundo widget, **Baterías**, muestra la carga del Mac (con el tiempo restante) y la de los accesorios Bluetooth conectados: teclado, ratón, trackpad, auriculares y AirPods (izquierdo, derecho y estuche por separado). Se actualiza cada 30 segundos. La barra cambia de color según la carga: **verde** a partir del 50 %, **amarillo** entre 25 y 49 %, **naranja** entre 10 y 24 % y **rojo** por debajo del 10 %. macOS no permite leer la batería del iPhone, el iPad ni el Apple Watch.

Los widgets se mueven arrastrándolos y recuerda su posición. Por defecto queda en el escritorio, debajo de las ventanas, como un widget normal. Desde el icono de la barra de menú puedes:

- mantenerlo encima de las ventanas
- mostrar el % de CPU en la barra de menú
- ocultarlo
- abrir la app al iniciar sesión

No necesita permisos especiales.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

Para revisar el diseño sin abrir la app: `/Applications/Monitor.app/Contents/MacOS/Monitor --snapshot widget.png`
