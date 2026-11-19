# Inicio (TV JVC) — contexto

Lee `LEEME.md`: tiene el TV, cómo compilar e instalar, y cómo dejarlo de inicio. Lee también `../CLAUDE.md`.

Datos que no están en el LEEME:

- **Para quitar Google como inicio** se desactivaron dos apps con `pm disable-user`: `launcherx` y
  `tungsten.setupwraith`. Sin desactivar la segunda sale una pantalla negra «Recovery».
  - Para revertir, `pm enable` a las dos.
- **Ajuste «Comportamiento cuando se enciende la TV»** (Ajustes → Sistema → Encendido y energía): lo dibuja
  launcherx, así que su panel sale vacío mientras está desactivado. Está en «Pantalla principal».
  - Para cambiarlo: `pm enable` launcherx, cambiar el ajuste, desactivarlo de nuevo y repetir
    `set-home-activity`.
- **Si el TV no responde,** busca en 192.168.5.x quién tiene el puerto 5555 antes de pensar que se dañó: la IP
  puede cambiar.
