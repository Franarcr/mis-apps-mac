# Barra

App de barra de menú para macOS (14+) que agrupa los iconos de la barra de menús, de cualquier app, para que no ocupen tanto (sobre todo en los MacBook con *notch*, donde los que no caben quedan tapados).

- Pone una **flecha ›** y, a su izquierda, una **línea │**.
- Los iconos que arrastres (manteniendo **⌘**) a la izquierda de la línea quedan **agrupados**: un clic en la flecha los esconde o los muestra.
- Los que dejes a la derecha de la flecha (por ejemplo Captura) se ven siempre.
- Después de mostrarlos, se vuelven a esconder solos a los 10 segundos (se puede desactivar).
- **Clic derecho** en la flecha: opciones, instrucciones y abrir al iniciar sesión.
- macOS recuerda la posición de cada icono, así que solo hay que ordenarlos una vez.

## Cómo funciona

Al plegar, la línea se estira hasta ocupar todo el sitio libre de la barra, y los iconos que tiene a su izquierda dejan de caber. No puede estirarse de más: en las versiones recientes de macOS, un elemento que no cabe se descarta él mismo en lugar de apartar a los demás. Por eso Barra mide la barra (posición de cada icono) y ajusta el largo en unos pocos pasos, y lo vuelve a ajustar al cambiar de app, porque cada app tiene un menú de distinto ancho. Si la línea quedara a la derecha de la flecha, la app avisa en lugar de esconder la flecha.

No necesita permisos.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
