# Historietas

Lector de cómics para macOS (14+). Abre archivos **CBZ**, **CBR**, **CB7** y **CBT**.

- Los cuatro formatos son archivos comprimidos con las imágenes de las páginas dentro (ZIP, RAR, 7z y TAR). La app los lee con la libarchive que trae macOS, y reconoce el formato por el contenido, así que también abre los `.cbr` que en realidad son ZIP (y al revés). Lee RAR 4 y RAR 5.
- Las páginas se ordenan como en el Finder (`page2` va antes que `page10`), y se ignora lo que no es una página: `__MACOSX`, archivos ocultos, `ComicInfo.xml`, `Thumbs.db`…
- **Ajuste**: página entera, ajustar al ancho (con desplazamiento vertical) o tamaño real.
- **Doble página**, con la portada sola para que las páginas enfrentadas queden bien emparejadas. Las páginas apaisadas (dobles ya unidas) se muestran solas.
- **Lectura de derecha a izquierda** para manga: invierte el orden de las páginas enfrentadas, las flechas, los clics y el deslizador.
- Recuerda **por qué página ibas** en cada cómic, y los últimos 15 abiertos (*Archivo › Abrir reciente*).
- Ampliar con el gesto de pellizco o ⌘+ / ⌘−. Con la página ampliada, se mueve arrastrándola.
- Para abrir un cómic: doble clic en el Finder, arrastrarlo al icono del Dock o a la ventana, o ⌘O. Cada cómic se abre en su propia ventana.

| Atajo | Acción |
| --- | --- |
| → / ← o clic en el tercio derecho / izquierdo | Página siguiente / anterior (al revés en manga) |
| Espacio / ⇧Espacio | Bajar por la página y, al llegar al final, pasar a la siguiente / volver |
| ↑ ↓ | Desplazarse por la página |
| Inicio / Fin, ⌘↑ / ⌘↓ | Primera / última página |
| ⌘G | Ir a una página |
| ⌘1 / ⌘2 / ⌘3 | Página entera / ajustar al ancho / tamaño real |
| ⌘D | Doble página |
| ⇧⌘D | Portada sola en doble página |
| ⇧⌘M | De derecha a izquierda (manga) |
| ⌘+ / ⌘− / ⌘0 | Ampliar / reducir / tamaño normal |
| ⌃⌘F | Pantalla completa (Esc para salir) |

No necesita permisos especiales. Los ajustes y la página de cada cómic se guardan en las preferencias de la app (`com.fran.historietas`).

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
