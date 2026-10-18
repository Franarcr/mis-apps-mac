# Captura

App de barra de menú para macOS (15+) inspirada en CleanShot.

| Acción | Atajo |
| --- | --- |
| Pantalla completa (la pantalla bajo el ratón) | ⌥⇧1 |
| Área (con lupa de píxeles y medidas) | ⌥⇧2 |
| Texto por OCR (español e inglés) → portapapeles | ⌥⇧3 |
| Grabar vídeo (área, o clic para toda la pantalla) · otra vez para detener | ⌥⇧4 |
| Captura con desplazamiento · otra vez para terminar | ⌥⇧5 |
| Grabar GIF (área, o clic para toda la pantalla) · otra vez para detener | ⌥⇧6 |

**Vídeo:** se graba en MP4 (60 fps, con cursor) en la carpeta de capturas y se copia el archivo al portapapeles. Por defecto incluye el sonido del sistema; el micrófono se activa en el menú *Audio de los vídeos*. Mientras graba, el icono de la barra se pone rojo con el tiempo; púlsalo para detener.

**Anotar:** en la miniatura, pulsa ✏️ o haz doble clic (o activa *Anotar tras capturar* en el menú). El editor tiene flecha, rectángulo, resaltado y texto, 6 colores y 3 grosores; las anotaciones se pueden seleccionar, mover, recolorear y borrar (el texto se edita con doble clic). ⌘Z deshace, ⌘C copia, ⌘S guarda en la carpeta de capturas y ⌘↩ (*Listo*) copia el resultado y cierra.

**GIF:** se graba como un vídeo sin sonido y al detenerlo se convierte en un GIF animado (12 fps, hasta 1000 px de ancho, en bucle) que se guarda en la carpeta de capturas y se copia al portapapeles.

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
- Anotaciones: `/Applications/Captura.app/Contents/MacOS/Captura --annotate-test imagen.png salida.png`
- GIF: `/Applications/Captura.app/Contents/MacOS/Captura --gif-test video.mp4 salida.gif`
- Unión de la captura con desplazamiento: `/Applications/Captura.app/Contents/MacOS/Captura --stitch-test imagen-alta.png`
