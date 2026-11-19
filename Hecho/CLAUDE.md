# Hecho — contexto

App de tareas propia, en español, inspirada en Things 3 (no una copia: nombre y diseño propios), para Mac y iPhone.
Lee `../CLAUDE.md` (reglas generales) e `INVESTIGACION.md` (investigación y plan de 3 etapas).

## Proyecto

- Un solo target multiplataforma SwiftUI + SwiftData: `Hecho.xcodeproj`, bundle `com.francho.hecho`.
- Datos en `Application Support/Hecho/Hecho.store` en cada equipo.
- Instalar: `./instalar-mac.sh` (a `/Applications`) y `./instalar-iphone.sh` (en «Francho», salta simuladores).

## Hecho hasta ahora

- **Etapa 1:** listas, áreas y proyectos estilo Things.
- **Etapa 2:**
  - Recordatorios con hora (UNUserNotification, se resincronizan en cada guardado en `Sync.swift`).
  - Repeticiones con dos modos (`RepeatRule.swift`); al completar una se crea la siguiente.
  - Eventos del calendario con EventKit (`CalendarFeed`, `CalendarExport`).
  - Widget «Hoy» solo en iPhone (`HechoWidgets/`), con un JSON en el app group `group.com.francho.hecho`. Su
    casilla deja en cola las tareas, y la app las completa al abrirse.
  - Botón + arrastrable con DragGesture propio (el drag&drop del sistema no funcionaba sobre un Button).
  - Menú «Ir» ⌘1–⌘7 en el Mac.
  - Fechas escritas en texto (`WhenParser.swift`).
- **Sincronización por Wi-Fi (`PeerSync.swift`):**
  - Bonjour `_hecho._tcp`, con intercambio del estado completo.
  - Gana el registro con `modifiedAt` más nuevo; los borrados quedan como marcas en UserDefaults.
  - Solo sincroniza con Hecho abierto en ambos equipos y en la misma red.
  - Mejoras subidas en f4536dd.

## Pendiente (solo si Fran lo pide)

Etapa 3: sincronización por iCloud (requiere cuenta de desarrollador de pago), Siri y Apple Watch (el reloj no se
empareja con Xcode).
