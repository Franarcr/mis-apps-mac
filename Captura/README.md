# Captura

App de barra de menú para macOS (15+) inspirada en CleanShot.

| Acción | Atajo |
| --- | --- |
| Pantalla completa (la pantalla bajo el ratón) | ⌥⇧1 |
| Área (con lupa de píxeles y medidas) | ⌥⇧2 |
| Texto por OCR (español e inglés) → portapapeles | ⌥⇧3 |
| Grabar vídeo (área, o clic para toda la pantalla) · otra vez para detener | ⌥⇧4 |
| Captura con desplazamiento · otra vez para terminar | ⌥⇧5 |

**Vídeo:** se graba en MP4 (60 fps, con cursor) en la carpeta de capturas y se copia el archivo al portapapeles. Por defecto incluye el sonido del sistema; el micrófono se activa en el menú *Audio de los vídeos*. Mientras graba, el icono de la barra se pone rojo con el tiempo; púlsalo para detener.

**Captura con desplazamiento:** selecciona la zona y desplázate hacia abajo con la rueda o el trackpad. Las cabeceras y pies fijos no se repiten, y se ignora la barra de desplazamiento. Si te desplazas demasiado rápido, el panel te avisa para que vuelvas un poco atrás. Cada intento queda registrado en `~/Library/Logs/Captura/desplazamiento.log`. Pulsa *Terminar* (o ⌥⇧5) y la imagen larga se copia como cualquier captura.

Por defecto, cada captura **solo se copia al portapapeles**. Si activas *Guardar también en archivo* en el menú, también se guarda como PNG en `~/Pictures/Capturas` (la carpeta se puede cambiar desde el menú).

Abajo a la izquierda aparece una miniatura que puedes arrastrar a otra app o usar para copiar, guardar o abrir la captura. Desaparece a los **3 segundos**; puedes cambiar ese tiempo en el menú *Ocultar miniatura tras* (2–15 s, o no mostrarla). Mientras tengas el ratón encima, no desaparece.

Para cancelar una selección, pulsa Esc o haz clic derecho.

## Compilar

```bash
./build.sh    # compila e instala en /Applications (única copia)
```

Si existe el certificado de `../crear-firma.sh`, la app se firma con él y conserva el permiso de **Grabación de pantalla** al recompilarla.

Pruebas sin permisos de pantalla:

- OCR: `/Applications/Captura.app/Contents/MacOS/Captura --ocr imagen.png`
- Unión de la captura con desplazamiento: `/Applications/Captura.app/Contents/MacOS/Captura --stitch-test imagen-alta.png`
