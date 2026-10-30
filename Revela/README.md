# Revela

Editor de fotos para macOS (14+), inspirado en Luminar Neo. Edita sin tocar la foto original (los ajustes se guardan aparte y se recuperan al volver a abrirla) y usa la IA que ya trae macOS, sin internet. Es una app normal con ventana.

## Qué hace

- **Abre** JPEG, HEIC, PNG, TIFF y RAW de cámara (Canon, Nikon, Sony, Fuji, DNG… los que admite macOS). Arrastra la foto a la ventana o al icono del Dock, o usa ⌘O.
- **Luz:** exposición, contraste, luces, sombras, blancos y negros.
- **Color:** temperatura, tinte, intensidad y saturación.
- **Detalle:** claridad (contraste local), nitidez y viñeta.
- **Looks:** Cine, Cálido, Frío, Película, Vintage, Cromo, Instantánea y dos de blanco y negro, con intensidad ajustable. **Importar LUT .cube** añade los tuyos (los de Lightroom, DaVinci o cámaras de cine).
- **Inteligencia artificial** (Vision, de Apple):
  - **Mejora automática**: ajusta luz y color en un clic.
  - **Enderezar horizonte**: detecta el horizonte y lo pone recto (también se puede enderezar a mano).
  - **Desenfocar fondo**: detecta el sujeto (personas, animales u objetos) y desenfoca lo demás, como el modo retrato.
  - **Luz del sujeto / Luz del fondo**: ilumina u oscurece por separado al sujeto y al fondo.
  - **Desenfoque de lente**: desenfoca según la distancia de cada punto, como un objetivo luminoso; el sujeto queda enfocado. Usa el modelo **Depth Anything V2** de Apple (licencia Apache 2.0, ~50 MB), que se descarga una sola vez con el botón *Descargar desenfoque de lente* y se guarda en `~/Library/Application Support/Revela/Modelos/`.
- **Borrar objetos** (LaMa, licencia Apache 2.0, conversión a Core ML de MLBoy, ~217 MB, se descarga una vez): pulsa *Pincel* y pinta sobre personas, cables, manchas o cualquier cosa; se rellena con lo que debería haber detrás. Solo se procesa un recorte alrededor de lo pintado, así la foto conserva su resolución completa. *Deshacer trazo* y *Quitar todo* lo revierten.
- **Selección con un clic** (SAM 2.1 de Apple, licencia Apache 2.0, ~94 MB, se descarga una vez): pulsa *Seleccionar* y haz clic en una persona, el agua, un edificio… (⌥ clic quita una zona; *Deshacer clic* quita el último). Cada clic suma su propia zona, así se pueden juntar cosas distintas. Luego ajusta solo esa zona: exposición, contraste, saturación y temperatura.
- **Cielo** (con el mismo modelo): *Luz del cielo* y *Realzar cielo* para el cielo de la foto, o **Cambiar cielo** por uno de los incluidos (despejado, con nubes, atardecer, hora dorada, tormenta) o por una foto de cielo tuya: *Añadir fotos de cielo…* las guarda en **Mis cielos** (`~/Library/Application Support/Revela/Cielos/`) para usarlas con un clic; clic derecho para quitar una. El cielo nuevo se coloca con su horizonte sobre el de la foto. **Armonizar con el cielo** hace que el paisaje tome el color y la luz del cielo nuevo (cálido con un atardecer, frío y apagado con una tormenta).
- **Agua** (con el mismo modelo): *Marcar el agua* y un clic en el mar, lago o río. Luego **Color del cielo en el agua** (toma el color medio del cielo, el cambiado si lo cambiaste, y conserva olas y brillos), **Reflejo del cielo** y **Luz del agua**.
- **Retrato** (detección de caras de macOS): **suavizar piel** (conserva textura), **ojos** más claros y nítidos y **dientes** más blancos, solo en las zonas de cada cara.
- **Antes / después** (botón *Antes* o la tecla `\`), **Deshacer** (⌘Z) y **Restablecer** (⇧⌘R). Doble clic en el nombre de un control lo devuelve a cero.
- **Exportar** (⌘E) en JPEG, HEIC, PNG o TIFF de 16 bits, a resolución completa.
- **Ampliar con IA al exportar** (Real-ESRGAN, licencia BSD-3, conversión a Core ML de MLBoy, ~67 MB, se descarga una vez): ×2 o ×4 recuperando detalle y quitando ruido. Se procesa en mosaicos de 512 px que se solapan. Hasta 120 megapíxeles de salida (un RAW de 24 MP a ×2 tarda algo más de un minuto en un M5).
- **Copiar ajustes / Pegar ajustes** (⇧⌘C / ⇧⌘V, o los botones de arriba): lleva el revelado de una foto a otra. No se copian los clics de selección y de agua, los trazos de borrar ni el enderezado, porque dependen de dónde está cada cosa en cada foto; al pegar, la foto conserva los suyos.
- **Aplicar a varias fotos** (⇧⌘E): revela un lote de fotos con los mismos ajustes (con el mismo criterio que *Copiar ajustes*) y las guarda en una carpeta.

## Lo que no hace (frente a Luminar)

Luminar trae unos 60 modelos de IA propios de Skylum (3,2 GB): borrado generativo, cambio de cielo, eliminar cables o polvo, ampliar ×2/×4/×6, reiluminar caras… Esos modelos no se pueden reutilizar. Revela usa la IA de macOS y modelos abiertos de uso libre (profundidad, selección, borrado y ampliación). El borrado de LaMa es bueno con objetos pequeños y medianos; en zonas grandes y con mucho detalle puede verse borroso.

## Para pruebas

```bash
# Revela una foto con ajustes de ejemplo (incluida la IA) y la exporta
/Applications/Revela.app/Contents/MacOS/Revela --prueba foto.jpg salida.jpg [look] [--lente]
# Descarga el modelo de profundidad (si falta) y muestra sus entradas y salidas
/Applications/Revela.app/Contents/MacOS/Revela --profundidad
# Descarga SAM 2.1 (si falta); con foto, guarda la zona de esos clics (x,y de 0 a 1, origen abajo a la izquierda)
/Applications/Revela.app/Contents/MacOS/Revela --seleccion [foto salida.jpg 0.5,0.4 …]
# Cambia el cielo de una foto (despejado, nubes, atardecer, dorado, tormenta o la ruta de una foto)
/Applications/Revela.app/Contents/MacOS/Revela --prueba foto.jpg salida.jpg --cielo atardecer
# Descarga LaMa (si falta); con foto, borra círculos x,y,radio (de 0 a 1, origen abajo a la izquierda)
/Applications/Revela.app/Contents/MacOS/Revela --borrar [foto salida.jpg 0.55,0.35,0.02 …]
# Exporta una foto con sus ajustes guardados (sin cambiarlos); --agua prueba el agua: x,y tono reflejo luz
/Applications/Revela.app/Contents/MacOS/Revela --revelar foto salida.jpg [--agua 0.75,0.2 60 30 0]
# Descarga Real-ESRGAN (si falta); con foto, amplía un recorte en píxeles y lo compara con una ampliación normal
/Applications/Revela.app/Contents/MacOS/Revela --ampliar [foto prefijo 4 x,y,ancho,alto]
```

Los ajustes de cada foto están en `~/Library/Application Support/Revela/ediciones.json` y los LUT importados en `~/Library/Application Support/Revela/LUT/`.

## Compilar

```bash
./build.sh
```
