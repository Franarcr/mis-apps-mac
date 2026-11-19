# Panel Claude

App para el Mac que lee lo que Claude guarda en este equipo y muestra:

- **Chats** de Claude Code y Cowork: tamaño, contexto (tokens que Claude relee en cada mensaje), mensajes y última actividad. Desde aquí se pueden mostrar en Finder o mandar a la Papelera.
- **Conectores** de claude.ai, **servidores MCP** y **extensiones**.
- **Plugins** y **habilidades** (de la cuenta, tuyas y de plugins).
- **Tareas programadas** y cuántas veces se han ejecutado.
- **Uso del plan** (límite de 5 horas y semanal) con su historial.
- **Espacio en disco** de cada carpeta de Claude, con opción de vaciar las cachés.
- **Avisos**: chats muy pesados, uso alto, servidores MCP rotos, etc.

También tiene un ícono en la barra de menú con el uso semanal.

Solo lee archivos. Lo único que borra es lo que mandes tú a la Papelera, y siempre pregunta antes.

## Compilar

```bash
./build.sh
```

Instala `/Applications/PanelClaude.app`.

## Artefacto de claude.ai

`PanelClaude --json <archivo>` exporta todo en JSON. `artefacto/exportar.py` lo reparte en cinco archivos que lee el tablero
https://claude.ai/artifact/FQwDHSJM5EEHBuLKagutwc. La tarea programada `panel-claude` los sube cada mañana.

## De dónde sale cada dato

| Dato | Archivo |
| --- | --- |
| Chats | `~/.claude/projects/*/*.jsonl` (títulos y archivado: `~/Library/Application Support/Claude/claude-code-sessions`) |
| Conectores | `remoteMcpServersConfig` de la sesión más reciente |
| MCP | `claude_desktop_config.json`, `~/.claude.json`, `extensions-installations.json` |
| Plugins | `~/Library/Application Support/Claude/plugin-list/*/*/plugins.json` |
| Habilidades | `local-agent-mode-sessions/skills-plugin`, `~/.claude/skills` y las carpetas de los plugins |
| Uso | `plan-usage-history.json` |

Los formatos son internos de Claude y pueden cambiar con una actualización.
