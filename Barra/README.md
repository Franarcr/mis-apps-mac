# Barra

App de barra de menú para macOS (14+) que junta en un solo icono las demás apps de barra de menús de este repositorio (Captura, Portapapeles, Puntos, Monitor, Ventanas y Volumen), para que la barra no se llene, sobre todo en los MacBook con *notch*.

- Un clic en su icono muestra la lista de esas apps, cada una con una marca.
- **Desmarcar** una app esconde su icono de la barra, pero la app **sigue funcionando**: sus atajos de teclado (por ejemplo ⌥⇧2 de Captura o ⌥⇧V de Portapapeles) y todo lo que hace siguen igual.
- Las apps escondidas aparecen en *Abrir el menú de*: al elegir una, se abre su menú donde está el puntero, con todas sus opciones.
- **Marcarla** de nuevo vuelve a mostrar su icono.
- Se recuerda aunque reinicies el Mac: cada app guarda si su icono va escondido.
- Captura muestra su icono mientras graba aunque esté escondido, porque es el botón para detener la grabación.

## Iconos de otras apps

macOS no deja que una app esconda el icono de otra. Para esos (Edge, Creative Cloud…) está *Esconder iconos de otras apps…*, que abre **Ajustes del Sistema › Barra de menús**, donde cada app tiene su interruptor y el icono se esconde sin cerrar la app.

## Cómo funciona

Cada app de barra de menús incluye `BarraLink.swift` (igual en todas). Barra guarda `iconHidden` en las preferencias de la app y le avisa con una notificación distribuida (`com.fran.barra.setHidden`); la app esconde su icono con `NSStatusItem.isVisible`. Para abrir su menú, Barra envía `com.fran.barra.showMenu` y la app lo muestra donde está el puntero.

No necesita permisos.

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

Después de instalar Barra por primera vez, vuelve a compilar las apps que quieras esconder (`./build.sh` en cada carpeta) para que incluyan la conexión con Barra.

La primera vez, `build.sh` genera el icono con [../iconos/crear-icono.swift](../iconos/crear-icono.swift).
