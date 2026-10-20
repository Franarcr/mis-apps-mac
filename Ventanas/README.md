# Ventanas

App de barra de menú para macOS (14+) que cambia el comportamiento de los botones de las ventanas.

- **Botón verde agranda la ventana**: la ventana ocupa toda la pantalla (sin tapar la barra de menús ni el Dock) en lugar de pasar a pantalla completa en otro escritorio. Otro clic la devuelve a su tamaño anterior. Si mantienes **⌥** pulsada, el botón hace lo de siempre. Viene activado.
- **Cerrar la app con el botón rojo**: en las apps que elijas, al cerrar su última ventana (con el botón rojo o ⌘W) la app se cierra del todo, en lugar de quedarse abierta en el Dock sin ventanas. Se eligen desde el icono de la barra de menú › *Cerrar la app con el botón rojo*, donde aparecen las apps abiertas. El Finder no se puede elegir.

## Permisos

Necesita el permiso de **Accesibilidad** para ver y mover las ventanas de otras apps. La primera vez macOS lo pide; actívalo en **Ajustes del Sistema › Privacidad y seguridad › Accesibilidad**. Las funciones arrancan solas en cuanto se concede, sin reiniciar la app.

## Limitaciones

- macOS solo informa de las ventanas del escritorio (Space) actual. Si una app elegida tiene ventanas en otro escritorio y cierras la última del escritorio actual, la app se cierra igual.
- Las apps que piden guardar los cambios lo siguen haciendo al cerrar la ventana, antes de que la app se cierre.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
