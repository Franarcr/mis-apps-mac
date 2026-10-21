# Ventanas

App de barra de menú para macOS (14+) que cambia el comportamiento de los botones de las ventanas.

- **Botón verde agranda la ventana**: la ventana ocupa toda la pantalla (sin tapar la barra de menús ni el Dock) en lugar de pasar a pantalla completa en otro escritorio. Otro clic la devuelve a su tamaño anterior. Si mantienes **⌥** pulsada, el botón hace lo de siempre. Viene activado.
- **Cerrar la app con el botón rojo**: si cierras con el botón rojo la última ventana de una app, la app se cierra del todo, en lugar de quedarse abierta en el Dock sin ventanas. Si la app pregunta antes si quieres guardar, se cierra después de que respondas. Viene activado en todas las apps menos el Finder. Desde el icono de la barra de menú › *Cerrar la app con el botón rojo* puedes desmarcar *En todas las apps* y elegir solo algunas. Cerrar la ventana con ⌘W no cierra la app.

## Permisos

Necesita el permiso de **Accesibilidad** para ver y mover las ventanas de otras apps. La primera vez macOS lo pide; actívalo en **Ajustes del Sistema › Privacidad y seguridad › Accesibilidad**. Las funciones arrancan solas en cuanto se concede, sin reiniciar la app.

## Limitaciones

- macOS solo informa de las ventanas del escritorio (Space) actual. Si una app elegida tiene ventanas en otro escritorio y cierras con el botón rojo la última del escritorio actual, la app se cierra igual.

## Si una app no se cierra con el botón rojo

En el menú › *Ver registro del botón rojo* se abre `~/Library/Logs/Ventanas.log`, que anota cada clic: si se reconoció el botón rojo y cuántas ventanas le quedaban a la app.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
