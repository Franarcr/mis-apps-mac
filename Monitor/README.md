# Monitor

Widget flotante para macOS (14+) que muestra en tiempo real (cada segundo) los recursos del Mac:

- **CPU**, **memoria** y **GPU**, con la gráfica de los últimos 60 segundos
- **Red**: bajada (↓ cian) y subida (↑ rosa)
- **Disco**: lectura (L naranja), escritura (E amarillo) y espacio libre
- **Batería**: porcentaje y estado de carga
- Los **3 procesos que más CPU usan**

El widget se mueve arrastrándolo y recuerda su posición. Por defecto queda en el escritorio, debajo de las ventanas, como un widget normal. Desde el icono de la barra de menú puedes:

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
