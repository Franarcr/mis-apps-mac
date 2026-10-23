# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.2,<2"]
# ///
"""Servidor MCP con los módulos de Oracle Forms convertidos a texto (ver README.md).

Uso:  uv run forms_mcp.py /ruta/a/la/carpeta/con/los/xml
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forms_xml  # noqa: E402

FOLDER = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FORMS_XML_DIR", ".")).expanduser()
MAX_RESULTS = 200

mcp = FastMCP("oracle-forms")
_modules: list[forms_xml.Module] = []
_errors: list[str] = []


def _load() -> None:
    global _modules, _errors
    _modules, _errors = forms_xml.load_folder(FOLDER)


def _find_module(name: str) -> forms_xml.Module | None:
    wanted = name.strip().upper()
    for module in _modules:
        if module.name.upper() == wanted or module.file.stem.upper() == wanted or module.file.name.upper() == wanted:
            return module
    return None


def _not_found(name: str) -> str:
    names = ", ".join(module.name for module in _modules[:50])
    return f"No hay ningún módulo llamado {name}. Módulos disponibles: {names}"


@mcp.tool()
def listar_modulos() -> str:
    """Lista los formularios, menús y librerías de Oracle Forms disponibles, con sus bloques y cuánto código tienen."""
    if not _modules:
        return f"No hay módulos en {FOLDER}. Convierte los .fmb con convertir.ps1 y copia la carpeta aquí."
    lines = [f"{len(_modules)} módulos en {FOLDER}:"]
    for module in _modules:
        blocks = ", ".join(block.name for block in module.blocks)
        lines.append(f"- {module.name} ({module.kind}, {module.file.name}): {len(module.code)} unidades de código"
                     + (f"; bloques: {blocks}" if blocks else ""))
    if _errors:
        lines += ["", "No se pudieron leer:"] + [f"- {error}" for error in _errors]
    return "\n".join(lines)


@mcp.tool()
def ver_modulo(nombre: str) -> str:
    """Estructura de un módulo: bloques con su tabla, ítems con su columna, relaciones, LOVs, parámetros,
    librerías y la lista de triggers y program units. Usa ver_codigo para leer el PL/SQL."""
    module = _find_module(nombre)
    return forms_xml.summary(module) if module else _not_found(nombre)


@mcp.tool()
def ver_codigo(modulo: str, nombre: str = "") -> str:
    """PL/SQL de un módulo. `nombre` filtra por trigger, program unit o ruta (p. ej. WHEN-VALIDATE-ITEM,
    CLIENTES.NOMBRE o VALIDAR_CLIENTE); vacío devuelve todo el código del módulo."""
    module = _find_module(modulo)
    if not module:
        return _not_found(modulo)
    wanted = nombre.strip().upper()
    units = [unit for unit in module.code
             if not wanted or unit.path.upper() == wanted or unit.name.upper() == wanted or wanted in unit.path.upper()]
    if not units:
        paths = ", ".join(unit.path for unit in module.code)
        return f"No hay código que coincida con {nombre} en {module.name}. Hay: {paths}"
    return "\n\n".join(f"-- {unit.kind}: {module.name}.{unit.path}\n{unit.text}" for unit in units)


@mcp.tool()
def buscar_codigo(texto: str, expresion_regular: bool = False) -> str:
    """Busca un texto (sin distinguir mayúsculas) en todo el PL/SQL y SQL de todos los módulos: triggers,
    program units, consultas de record groups y comandos de menú. Devuelve módulo, código, línea y el texto."""
    try:
        pattern = re.compile(texto if expresion_regular else re.escape(texto), re.IGNORECASE)
    except re.error as error:
        return f"La expresión regular no es válida: {error}"
    results = []
    for module in _modules:
        for unit in module.code:
            for number, line in enumerate(unit.lines, start=1):
                if pattern.search(line):
                    results.append(f"{module.name} · {unit.kind} {unit.path} · línea {number}: {line.strip()}")
                    if len(results) >= MAX_RESULTS:
                        return "\n".join(results + [f"(se muestran los primeros {MAX_RESULTS}; afina la búsqueda)"])
    return "\n".join(results) if results else f"No aparece «{texto}» en el código."


@mcp.tool()
def uso_de_tabla(tabla: str, columna: str = "") -> str:
    """Dónde se usa una tabla (o vista) y, opcionalmente, una de sus columnas: bloques que la consultan o
    modifican, ítems enlazados a la columna, y código o consultas que la nombran."""
    table = tabla.strip().upper()
    column = columna.strip().upper()
    word = re.compile(rf"\b{re.escape(table)}\b", re.IGNORECASE)
    column_word = re.compile(rf"\b{re.escape(column)}\b", re.IGNORECASE) if column else None
    blocks, items, code = [], [], []
    for module in _modules:
        for block in module.blocks:
            if table in (block.source.upper(), block.dml_target.upper()):
                blocks.append(f"- {module.name}.{block.name} (origen {block.source or '—'}, DML {block.dml_target or '—'})")
                for item in block.items:
                    if column and item.column.upper() == column:
                        items.append(f"- {module.name}.{block.name}.{item.name} ({item.item_type}, {item.prompt})")
        for unit in module.code:
            if word.search(unit.text) and (not column_word or column_word.search(unit.text)):
                code.append(f"- {module.name} · {unit.kind} {unit.path}")
    title = f"{table}.{column}" if column else table
    out = [f"Uso de {title}:", "", "Bloques basados en la tabla:"] + (blocks or ["- ninguno"])
    if column:
        out += ["", f"Ítems enlazados a {column}:"] + (items or ["- ninguno"])
    out += ["", "Código que la nombra" + (f" junto con {column}" if column else "") + ":"] + (code or ["- ninguno"])
    return "\n".join(out)


@mcp.tool()
def recargar() -> str:
    """Vuelve a leer la carpeta (después de copiar XML nuevos o actualizados)."""
    _load()
    return listar_modulos()


if __name__ == "__main__":
    _load()
    mcp.run()
