# Inicio (TV LG) — contexto

Lee `LEEME.md` (emparejar con ares, compilar e instalar) y `../CLAUDE.md`.

- **El TV:** LG 55NANO79SNA (webOS 5.6) en 192.168.5.103. En ares está registrado como el dispositivo `lgsala`,
  con la llave en `~/.ssh/lgsala_webos`.
- **La app:** es una app web, `local.fran.inicio`. Fran la abre con la tecla 1 del control, porque el botón Home
  no se puede cambiar sin root.
- **Si ares da error de autenticación:**
  1. Abre la app Developer Mode en el TV.
  2. Revisa que Key Server esté encendido.
  3. Repite `ares-novacom --getkey`. La passphrase cambia cada vez.
- **El Modo desarrollador caduca.** Se renueva desde esa misma app con la cuenta de desarrollador LG de Fran.
