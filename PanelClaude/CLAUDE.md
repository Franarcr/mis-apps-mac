# Panel Claude — contexto

Lee `README.md` (qué muestra y de dónde sale cada dato) y `../CLAUDE.md` (reglas generales).

- App del Mac `com.fran.panelclaude`: chats pesados, conectores, MCP, plugins, habilidades, tareas, uso del plan y
  disco. Solo lee; lo único que borra es lo que Fran manda a la Papelera, con confirmación.
- `PanelClaude --json <archivo>` exporta todo, y `artefacto/exportar.py` lo reparte en 5 JSON (chats,
  configuracion, uso, espacio, avisos).
- Esos 5 JSON alimentan el tablero https://claude.ai/artifact/FQwDHSJM5EEHBuLKagutwc (tipo Data, como archivos
  subidos).
- La tarea programada `panel-claude` (7:30 cada día, modo Auto) vuelve a subir los JSON y borra los viejos.
- Los chats de claude.ai web no están en el equipo: solo los de Claude Code y Cowork.
- Los formatos son internos de Claude y pueden cambiar con una actualización.
- Compilar: `./build.sh` → `/Applications/PanelClaude.app`.
