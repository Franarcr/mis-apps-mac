"""Lee los módulos de Oracle Forms convertidos a texto y los deja listos para consultar.

- Formularios, menús y bibliotecas de objetos: el XML que genera frmf2xml (form_fmb.xml, menu_mmb.xml, lib_olb.xml).
- Librerías PL/SQL: el .pld que genera frmcmp con script=YES.

Del XML se queda con lo que importa para entender el módulo (bloques, ítems, relaciones, LOVs, record groups,
parámetros, librerías) y con todo el PL/SQL (triggers, program units, consultas de record groups y comandos
de menú). Deja fuera las propiedades visuales (coordenadas, colores, fuentes), que son la mayor parte del XML.

Solo usa la biblioteca estándar de Python.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

# Elementos que agrupan objetos con nombre; forman la «ruta» de un trigger (BLOQUE.ITEM.TRIGGER).
_CONTAINERS = {"FormModule", "MenuModule", "ObjectLibrary", "Block", "Item", "Menu", "MenuItem", "Canvas",
               "Window", "LOV", "RecordGroup", "ObjectGroup", "PropertyClass", "Alert", "ObjectLibraryTab"}

# Atributos con código, y de qué tipo es ese código.
_CODE_ATTRIBUTES = {
    "TriggerText": "Trigger",
    "ProgramUnitText": "Program unit",
    "RecordGroupQuery": "Consulta de record group",
    "CommandText": "Comando de menú",
}


@dataclass
class CodeUnit:
    """Un trozo de PL/SQL o SQL: un trigger, un program unit, la consulta de un record group…"""

    module: str
    kind: str
    path: str  # p. ej. CLIENTES.NOMBRE.WHEN-VALIDATE-ITEM
    text: str

    @property
    def name(self) -> str:
        return self.path.rsplit(".", 1)[-1]

    @property
    def lines(self) -> list[str]:
        return self.text.splitlines()


@dataclass
class Item:
    name: str
    item_type: str = ""
    column: str = ""
    data_type: str = ""
    prompt: str = ""
    lov: str = ""
    required: bool = False
    database_item: bool = True


@dataclass
class Block:
    name: str
    source: str = ""  # tabla, vista o procedimiento de consulta
    source_type: str = ""
    dml_target: str = ""
    where: str = ""
    order_by: str = ""
    items: list[Item] = field(default_factory=list)
    relations: list[tuple[str, str, str]] = field(default_factory=list)  # (nombre, bloque detalle, condición)


@dataclass
class Module:
    name: str
    kind: str  # Formulario, Menú, Biblioteca de objetos, Librería PL/SQL
    file: Path
    title: str = ""
    blocks: list[Block] = field(default_factory=list)
    lovs: list[tuple[str, str]] = field(default_factory=list)  # (LOV, record group)
    record_groups: list[str] = field(default_factory=list)
    parameters: list[tuple[str, str]] = field(default_factory=list)  # (nombre, tipo)
    libraries: list[str] = field(default_factory=list)
    alerts: list[tuple[str, str]] = field(default_factory=list)  # (nombre, mensaje)
    windows: list[str] = field(default_factory=list)
    canvases: list[str] = field(default_factory=list)
    code: list[CodeUnit] = field(default_factory=list)


def _local(tag: str) -> str:
    """Quita el espacio de nombres: {http://xmlns.oracle.com/Forms}Block → Block."""
    return tag.rsplit("}", 1)[-1]


def _bool(value: str | None) -> bool:
    return (value or "").strip().lower() == "true"


_MODULE_KINDS = {"FormModule": "Formulario", "MenuModule": "Menú", "ObjectLibrary": "Biblioteca de objetos"}


def load_xml(path: Path) -> Module:
    root = ET.parse(path).getroot()
    top = next((child for child in root if _local(child.tag) in _MODULE_KINDS), root)
    module = Module(name=top.get("Name") or path.stem, kind=_MODULE_KINDS.get(_local(top.tag), "Módulo"),
                    file=path, title=top.get("Title") or "")

    def walk(element: ET.Element, owners: list[str]) -> None:
        tag = _local(element.tag)
        name = element.get("Name") or ""

        if tag == "Block":
            module.blocks.append(Block(
                name=name, source=element.get("QueryDataSourceName") or "",
                source_type=element.get("QueryDataSourceType") or "", dml_target=element.get("DMLDataTargetName") or "",
                where=element.get("WhereClause") or "", order_by=element.get("OrderByClause") or ""))
        elif tag == "Item" and module.blocks and owners and owners[-1] == module.blocks[-1].name:
            module.blocks[-1].items.append(Item(
                name=name, item_type=element.get("ItemType") or "", column=element.get("ColumnName") or "",
                data_type=element.get("DataType") or "", prompt=element.get("Prompt") or "",
                lov=element.get("LovName") or "", required=_bool(element.get("Required")),
                database_item=element.get("DatabaseItem", "true").lower() != "false"))
        elif tag == "Relation" and module.blocks:
            module.blocks[-1].relations.append((name, element.get("DetailBlock") or "", element.get("JoinCondition") or ""))
        elif tag == "LOV":
            module.lovs.append((name, element.get("RecordGroupName") or ""))
        elif tag == "RecordGroup":
            module.record_groups.append(name)
        elif tag in ("ModuleParameter", "FormParameter"):
            module.parameters.append((name, element.get("ParameterDataType") or ""))
        elif tag == "AttachedLibrary":
            module.libraries.append(element.get("LibraryLocation") or name)
        elif tag == "Alert":
            module.alerts.append((name, element.get("AlertMessage") or ""))
        elif tag == "Window" and len(owners) <= 1:
            module.windows.append(name)
        elif tag == "Canvas" and len(owners) <= 1:
            module.canvases.append(name)

        for attribute, kind in _CODE_ATTRIBUTES.items():
            text = element.get(attribute)
            if text and text.strip():
                path_parts = owners[1:] + ([name] if name else [])
                module.code.append(CodeUnit(module.name, kind, ".".join(path_parts) or module.name, text.rstrip()))

        child_owners = owners + [name] if tag in _CONTAINERS and name else owners
        for child in element:
            walk(child, child_owners)

    walk(top, [])
    return module


# En un .pld, cada program unit empieza en la columna 0 con PROCEDURE, FUNCTION o PACKAGE [BODY].
_PLD_UNIT = re.compile(r"^(PROCEDURE|FUNCTION|PACKAGE\s+BODY|PACKAGE)\s+([\w$#\"]+)", re.IGNORECASE | re.MULTILINE)


def _read_text(path: Path) -> str:
    data = path.read_bytes()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


def load_pld(path: Path) -> Module:
    text = _read_text(path).replace("\r\n", "\n")
    module = Module(name=path.stem.upper(), kind="Librería PL/SQL", file=path)
    starts = list(_PLD_UNIT.finditer(text))
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        kind = match.group(1).upper()
        kind = "Package body" if kind.startswith("PACKAGE") and "BODY" in kind else kind.capitalize()
        name = match.group(2).strip('"').upper()
        if kind == "Package body":
            name += " (body)"
        module.code.append(CodeUnit(module.name, kind, name, text[match.start():end].rstrip()))
    if not starts and text.strip():
        module.code.append(CodeUnit(module.name, "Código", module.name, text.rstrip()))
    return module


def load_folder(folder: Path) -> tuple[list[Module], list[str]]:
    """Todos los módulos de la carpeta (y subcarpetas). Devuelve también los archivos que no se pudieron leer."""
    modules: list[Module] = []
    errors: list[str] = []
    for path in sorted(folder.rglob("*")):
        suffix = path.suffix.lower()
        if not path.is_file() or suffix not in (".xml", ".pld"):
            continue
        try:
            modules.append(load_xml(path) if suffix == ".xml" else load_pld(path))
        except (ET.ParseError, OSError) as error:
            errors.append(f"{path.name}: {error}")
    return modules, errors


# MARK: Texto para leer


def _code_list(module: Module) -> list[str]:
    lines = []
    for unit in module.code:
        lines.append(f"- {unit.kind}: `{unit.path}` ({len(unit.lines)} líneas)")
    return lines


def summary(module: Module) -> str:
    """Resumen en Markdown: estructura del módulo y lista de su código (sin el código)."""
    out = [f"# {module.name} — {module.kind}", f"Archivo: `{module.file.name}`"]
    if module.title:
        out.append(f"Título: {module.title}")
    if module.parameters:
        out += ["", "## Parámetros"] + [f"- {name} ({kind})" if kind else f"- {name}" for name, kind in module.parameters]
    if module.libraries:
        out += ["", "## Librerías adjuntas"] + [f"- {library}" for library in module.libraries]
    for block in module.blocks:
        source = block.source or "(sin tabla: bloque de control)"
        out += ["", f"## Bloque {block.name}", f"- Origen: {source}" + (f" ({block.source_type})" if block.source_type else "")]
        if block.dml_target and block.dml_target != block.source:
            out.append(f"- Destino DML: {block.dml_target}")
        if block.where:
            out.append(f"- WHERE: `{block.where}`")
        if block.order_by:
            out.append(f"- ORDER BY: `{block.order_by}`")
        for name, detail, condition in block.relations:
            out.append(f"- Relación {name} → bloque {detail}: `{condition}`")
        if block.items:
            out += ["", "| Ítem | Tipo | Columna | Dato | Etiqueta | LOV | Oblig. |", "|---|---|---|---|---|---|---|"]
            for item in block.items:
                column = item.column if item.database_item else "(no de base)"
                out.append(f"| {item.name} | {item.item_type} | {column} | {item.data_type} | {item.prompt} | "
                           f"{item.lov} | {'sí' if item.required else ''} |")
    if module.lovs:
        out += ["", "## LOVs"] + [f"- {name} (record group {group})" for name, group in module.lovs]
    if module.alerts:
        out += ["", "## Alertas"] + [f"- {name}: {message}" for name, message in module.alerts]
    if module.windows or module.canvases:
        out += ["", "## Ventanas y canvas", f"- Ventanas: {', '.join(module.windows) or '—'}",
                f"- Canvas: {', '.join(module.canvases) or '—'}"]
    if module.code:
        out += ["", "## Código"] + _code_list(module)
    return "\n".join(out)


def full_text(module: Module) -> str:
    """Resumen más todo el código, para guardarlo en un archivo o pegarlo en una conversación."""
    out = [summary(module)]
    for unit in module.code:
        out += ["", f"### {unit.kind}: {unit.path}", "```sql", unit.text, "```"]
    return "\n".join(out)
