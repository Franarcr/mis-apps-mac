# Mis apps para Mac

Apps para macOS con chip Apple, escritas en Swift sin Xcode (solo con las Command Line Tools). Casi todas viven en la barra de menú; Historietas, Compresor, Lazo, Grabador y Revela tienen ventana y viven en el Dock.

| App | Qué hace | macOS |
| --- | --- | --- |
| [Captura](Captura/) | Capturas de pantalla completa o de área con anotaciones (flechas, cuadros, texto), OCR, vídeo con audio, GIF y capturas largas con desplazamiento (al estilo de CleanShot) | 15+ |
| [Portapapeles](Portapapeles/) | Historial de las últimas 100 copias, con buscador (⌥⇧V), y pegar sin formato (⌥⇧⌘V) | 14+ |
| [Puntos](Puntos/) | Bloc de 7 notas con Markdown en vivo, al estilo de Tot (⌥⇧N) | 14+ |
| [Monitor](Monitor/) | Widget de escritorio con CPU, memoria, GPU, temperatura, consumo, red, disco, batería y procesos en tiempo real | 14+ |
| [Ventanas](Ventanas/) | El botón verde agranda la ventana sin pantalla completa, y el rojo cierra del todo las apps que elijas | 14+ |
| [Volumen](Volumen/) | Volumen de cada app por separado, de silencio a 150 % | 14.2+ |
| [Compresor](Compresor/) | Abrir, extraer y crear comprimidos (ZIP con AES-256, 7z, RAR 4/5, TAR…), con Servicios del Finder, al estilo de WinZip | 14+ |
| [Lazo](Lazo/) | Colocar ventanas con la cuadrícula de cada monitor (⌥⇧L sobre la ventana), zonas con atajo y arrastre con ⌃⌥, al estilo de Lasso | 14+ |
| [Grabador](Grabador/) | Grabar imágenes de sistemas (.img, .iso, .zip, .xz…) en USB y tarjetas SD con verificación, al estilo de balenaEtcher | 14+ |
| [Revela](Revela/) | Editor de fotos (también RAW) con ajustes, looks, LUT .cube y la IA de macOS: desenfocar fondo, luz del sujeto, enderezar horizonte. Inspirado en Luminar | 14+ |
| [Historietas](Historietas/) | Lector de cómics CBZ, CBR, CB7 y CBT, con doble página, lectura de manga y la página por la que ibas | 14+ |

Para instalarlas desde los `.zip` de *Releases*, sigue [INSTALAR.md](INSTALAR.md).

## Compilar

Una sola vez, crea el certificado de firma local para que macOS conserve los permisos al recompilar:

```bash
./crear-firma.sh
```

Después, cada app se compila e instala en `/Applications` con su script:

```bash
cd Captura && ./build.sh
```

Para generar los `.zip` y las instrucciones en `dist/`:

```bash
./empaquetar.sh
```

Los iconos se generan con [iconos/crear-icono.swift](iconos/crear-icono.swift).
