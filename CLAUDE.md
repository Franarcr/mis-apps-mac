# Rea — apps caseras de Fran

Fran vive en Costa Rica. Esta carpeta tiene sus apps para Mac, iPhone, iPad y TVs. Cada proyecto activo tiene su
propio `CLAUDE.md` con el detalle; léelo antes de tocar ese proyecto y ponlo al día cuando cambie algo importante.

## Cómo trabajar con Fran (no negociable)

1. **Siempre en español**, breve y simple. Nunca en inglés, tampoco en resúmenes ni botones.
2. **Explicar y esperar un «sí».** Una idea o un deseo es una petición de propuesta: explica en palabras simples qué
   harías, qué verá y dónde, y espera su orden antes de crear archivos.
3. **No hacer commit ni push hasta que confirme** que funciona (o lo pida). Los commits terminan con
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
4. Antes de dar algo por arreglado, compruébalo como lo verá él (en la app, en el dispositivo).
5. Nada de números inventados en salud: salen de sus datos o de un estudio citado (ver `Vital/CLAUDE.md`).

## Equipos

- **Mac** «Titania». Apps de Mac: Swift Package + `./build.sh` que compila, firma con «Fran Firma Local»
  (`crear-firma.sh`; así macOS conserva los permisos) e instala en `/Applications`. Se montan fuera de Documentos
  porque iCloud sincroniza Documentos y rompe la firma.
- **iPhone 13 Pro Max** «Francho», UDID `00008110-00011CE23C33801E` (sin Apple Intelligence).
- **iPad Air 4**, UDID `00008101-000674862E01001E`, Modo desarrollador activo.
- **Apple Watch Series 12**: no logra emparejarse con Xcode, así que no hay apps propias en el reloj.
- Firma: equipo personal gratuito **CQNAH77456**; las apps de iPhone/iPad **caducan a los 7 días**. Antes de
  reinstalar, aparta los perfiles viejos de esa app en `~/Library/Developer/Xcode/UserData/Provisioning Profiles`
  (Xcode los reutiliza). Para un dispositivo nuevo compila con `-destination id=<UDID>`, no «iOS genérico».
- Instalar: `xcrun devicectl device install app --device <UDID> <ruta.app>`; el dispositivo debe estar desbloqueado.

## Proyectos

| Carpeta | Qué es | Estado |
| --- | --- | --- |
| `Vital/` | App de salud estilo Bevel (iPhone + widgets) | Activa, ver su CLAUDE.md |
| `Oido/` + `Barra/` | Graba y resume llamadas en el Mac; Barra agrupa los iconos de la barra de menús | Activa |
| `Hecho/` | Tareas estilo Things (Mac + iPhone) | Etapas 1–2 + sincronización Wi-Fi |
| `Kvlt/` | «Rockola», trivia musical para el iPad | Activa |
| `iPadCleaner/` | «Cleaner», limpieza del iPad | Terminada |
| `Mascota/` | Tuqui, el tucán que camina por la pantalla del Mac | Nueva |
| `PanelClaude/` | Panel de Claude (chats, uso, MCP) en el Mac y en un artefacto | Nueva |
| `InicioTV/`, `InicioMiTV/`, `InicioLG/` | Pantalla de inicio estilo Apple TV en los 3 TVs | Terminadas (datos en la memoria) |
| Resto (Captura, Portapapeles, Revela, …) | Apps de barra de menús y utilidades del Mac | Terminadas |

Tareas programadas aparte: `cobros-naret` (cobros del condominio) y `filtro-publicidad` (correo); sus detalles
están en la memoria de Claude.
