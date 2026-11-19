#!/usr/bin/env python3
"""Genera los archivos JSON que lee el artefacto «Panel Claude» de claude.ai.

Uso: python3 -I exportar.py <carpeta de salida>
Ejecuta la app PanelClaude en modo --json y reparte la foto en cinco archivos
de filas: chats, configuracion, uso, espacio y avisos.
"""
import json
import os
import subprocess
import sys

APP = "/Applications/PanelClaude.app/Contents/MacOS/PanelClaude"


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    snap_path = os.path.join(out, "snap.json")
    subprocess.run([APP, "--json", snap_path], check=True, timeout=600)
    with open(snap_path) as f:
        s = json.load(f)

    chats = [{
        "id": c["id"],
        "titulo": c["title"],
        "proyecto": c["project"],
        "mb": round(c["bytes"] / 1e6, 1),
        "contexto": c["contextTokens"],
        "mensajes": c["prompts"],
        "respuestas": c["replies"],
        "modelo": c["model"],
        "ultima": c.get("lastActivity"),
        "archivado": "sí" if c["archived"] else "no",
        "tarea": c.get("scheduledTask") or "",
    } for c in s["chats"]]

    config = []
    for c in s["connectors"]:
        config.append({"tipo": "Conector", "nombre": c["name"], "origen": "claude.ai",
                       "detalle": f'{c["tools"]} herramientas', "activo": "sí"})
    for m in s["mcpServers"]:
        tipo = "Extensión" if m["source"] == "Extensión" else "Servidor MCP"
        config.append({"tipo": tipo, "nombre": m["name"], "origen": m["source"],
                       "detalle": m["detail"], "activo": "sí"})
    for p in s["plugins"]:
        config.append({"tipo": "Plugin", "nombre": p["name"], "origen": p["source"],
                       "detalle": f'{p["skills"]} habilidades', "activo": "sí" if p["enabled"] else "no"})
    for k in s["skills"]:
        origen = {"Cuenta": "Cuenta de claude.ai", "Personal": "Tuya"}.get(k["source"], f'Plugin {k["source"]}')
        config.append({"tipo": "Habilidad", "nombre": k["name"], "origen": origen,
                       "detalle": k["description"][:160], "activo": "sí"})
    for t in s["tasks"]:
        config.append({"tipo": "Tarea programada", "nombre": t["name"], "origen": "Este Mac",
                       "detalle": f'{t["runs"]} ejecuciones', "activo": "sí"})

    uso = [{"fecha": u["date"], "limite_5h": u["fiveHour"], "limite_semanal": u["sevenDay"]} for u in s["usage"]]
    espacio = [{"nombre": d["name"], "gb": round(d["bytes"] / 1e9, 2), "nota": d["note"]} for d in s["disk"]]
    nivel = {"alert": "alerta", "warn": "atención", "info": "info"}
    avisos = [{"nivel": nivel[w["level"]], "texto": w["text"]} for w in s["warnings"]]

    for name, rows in [("chats", chats), ("configuracion", config), ("uso", uso),
                       ("espacio", espacio), ("avisos", avisos)]:
        with open(os.path.join(out, f"{name}.json"), "w") as f:
            json.dump(rows, f, ensure_ascii=False)
    os.remove(snap_path)
    print(json.dumps({"generado": s["generatedAt"], "chats": len(chats), "config": len(config),
                      "uso": len(uso), "espacio": len(espacio), "avisos": len(avisos)}))


if __name__ == "__main__":
    main()
