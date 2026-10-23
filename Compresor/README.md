# Compresor

Compresor y extractor de archivos para macOS (14+), inspirado en WinZip y Archiver. Usa la biblioteca de compresión que ya trae macOS (libarchive), sin motores de terceros.

- **Abre y extrae** ZIP, 7z, **RAR 4 y RAR 5** (también divididos en partes: `.part1.rar…` o `.rar` + `.r00…`), TAR, GZ, BZ2, XZ, ISO, CAB, CPIO, XAR, JAR…
- **Crea** ZIP (con **contraseña AES-256** opcional), 7z, TAR.GZ y TAR.XZ.
- Lista el contenido sin descomprimir, con buscador; extrae todo o solo lo seleccionado; **vista rápida** (⌘Y) y doble clic para abrir un archivo.
- **Extraer aquí** inteligente: si el comprimido trae una sola carpeta, la deja tal cual; si trae varios archivos sueltos, los agrupa en una carpeta. Nunca sobrescribe.
- **Servicios del Finder** (clic derecho): *Comprimir con Compresor*, *Comprimir con Compresor…* (eligiendo formato y contraseña) y *Extraer aquí con Compresor*.
- Suelta archivos en la ventana o en el icono del Dock: los comprimidos se abren y el resto se comprime.

**Límites de RAR:** se pueden abrir y extraer, pero no crear (el formato es propietario de WinRAR). Los RAR **con contraseña** no se pueden abrir: la biblioteca de macOS no admite su cifrado, y Compresor lo avisa claramente.

## Compilar y probar

```bash
./build.sh                                   # compila e instala en /Applications
.build/release/Compresor --self-test         # crea, lista y extrae en todos los formatos
.build/release/Compresor --list archivo.rar
.build/release/Compresor --extract archivo.rar destino [contraseña]
.build/release/Compresor --compress zip salida.zip [--password X] carpeta…
```
