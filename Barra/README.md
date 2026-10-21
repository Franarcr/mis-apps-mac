# Barra

App de barra de menú para macOS (14+) para tener menos iconos en la barra de menús, sobre todo en los MacBook con *notch*, donde los que no caben quedan tapados.

- Un clic en su icono muestra todas las apps que tienen icono en la barra, cada una con una marca.
- **Desmarcar** una app la cierra, y su icono desaparece. **Marcarla** la vuelve a abrir.
- Las apps de barra de menús que desmarcaste (las que solo viven en la barra, como Captura o Creative Cloud) se vuelven a cerrar solas si se abren al iniciar sesión.
- Las apps normales con icono en la barra (como Edge) aparecen con *(cierra la app)*: al desmarcarlas se cierra la app entera. Se pueden volver a abrir cuando quieras; no se cierran solas.
- *Ocultar iconos sin cerrar las apps…* abre Ajustes del Sistema › Barra de menús, donde macOS deja esconder iconos sin cerrar la app.

## Por qué cierra las apps en lugar de esconder su icono

En las versiones recientes de macOS, una app no puede esconder el icono de otra: el sistema decide cómo se colocan. La primera versión de Barra lo intentaba con el truco de Hidden Bar (estirar un separador para empujar los iconos fuera de la pantalla) y no funcionaba. Cerrar la app sí funciona siempre, y para esconder sin cerrar está la opción de Ajustes.

No necesita permisos.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
