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
- **Antes / después** (botón *Antes* o la tecla `\`), **Deshacer** (⌘Z) y **Restablecer** (⇧⌘R). Doble clic en el nombre de un control lo devuelve a cero.
- **Exportar** (⌘E) en JPEG, HEIC, PNG o TIFF de 16 bits, a resolución completa.
- **Aplicar a varias fotos** (⇧⌘E): revela un lote de fotos con los mismos ajustes y las guarda en una carpeta.

## Lo que no hace (frente a Luminar)

Luminar trae unos 60 modelos de IA propios de Skylum (3,2 GB): borrado generativo, cambio de cielo, retoque de piel, eliminar cables o polvo, ampliar ×2/×4/×6, reiluminar caras… Esos modelos no se pueden reutilizar y entrenarlos es un trabajo de años, así que Revela se limita a la IA incluida en macOS.

## Para pruebas

```bash
# Revela una foto con ajustes de ejemplo (incluida la IA) y la exporta
/Applications/Revela.app/Contents/MacOS/Revela --prueba foto.jpg salida.jpg [look]
```

Los ajustes de cada foto están en `~/Library/Application Support/Revela/ediciones.json` y los LUT importados en `~/Library/Application Support/Revela/LUT/`.

## Compilar

```bash
./build.sh
```
