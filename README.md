# Mis apps para Mac

Cuatro apps de barra de menú para macOS con chip Apple, escritas en Swift sin Xcode (solo con las Command Line Tools).

| App | Qué hace | macOS |
| --- | --- | --- |
| [Captura](Captura/) | Capturas de pantalla completa o de área con anotaciones (flechas, cuadros, texto), OCR, vídeo con audio, GIF y capturas largas con desplazamiento (al estilo de CleanShot) | 15+ |
| [Portapapeles](Portapapeles/) | Historial de las últimas 100 copias, con buscador (⌥⇧V) | 14+ |
| [Puntos](Puntos/) | Bloc de 7 notas con Markdown en vivo, al estilo de Tot (⌥⇧N) | 14+ |
| [Monitor](Monitor/) | Widget de escritorio con CPU, memoria, GPU, red, disco, batería y procesos en tiempo real | 14+ |

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

Para generar los tres `.zip` y las instrucciones en `dist/`:

```bash
./empaquetar.sh
```

Los iconos se generan con [iconos/crear-icono.swift](iconos/crear-icono.swift).
