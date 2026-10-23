"""Convierte los XML de Forms (y los .pld) en un Markdown legible por módulo: estructura y todo su código.

Sirve para leerlos uno mismo o pegarlos en una conversación con Claude sin el servidor MCP.

Uso:  python3 resumir.py <carpeta con los xml> [carpeta de salida]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forms_xml  # noqa: E402


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1]).expanduser()
    target = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else source / "resumen"
    target.mkdir(parents=True, exist_ok=True)
    modules, errors = forms_xml.load_folder(source)
    for module in modules:
        path = target / f"{module.name}.md"
        path.write_text(forms_xml.full_text(module), encoding="utf-8")
        print(f"{module.name}: {len(module.blocks)} bloques, {len(module.code)} unidades de código → {path.name}")
    for error in errors:
        print(f"No se pudo leer {error}", file=sys.stderr)
    print(f"\n{len(modules)} módulos resumidos en {target}")


if __name__ == "__main__":
    main()
