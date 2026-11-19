# Barra — contexto

Lee `README.md` (qué hace y cómo funciona) y `../CLAUDE.md` (reglas generales).

- Junta en un icono las apps de barra de menús del repo; esconder una solo oculta su icono, la app sigue funcionando.
- Comunicación por notificaciones distribuidas: `com.fran.barra.setHidden` y `com.fran.barra.showMenu`.
  Cada app incluye el mismo `BarraLink.swift`; si cambias uno, cópialo igual a todas (Oido, Mascota, Captura…).
- Oído aparece en «Abrir el menú de» siempre que está abierto (aunque no esté marcado como escondido), para poder
  detener una grabación.
- Desde su menú también se abren las apps cerradas (2fe4d48).
- Compilar: `./build.sh` → `/Applications/Barra.app`.
