# Forms MCP

Servidor MCP para que Claude Desktop pueda leer los módulos de **Oracle Forms**: formularios, menús, bibliotecas de objetos y librerías PL/SQL. Se usa junto al **SQLcl MCP**, así Claude puede cruzar un form con la base de datos (por ejemplo, ver un trigger y el paquete al que llama).

Ejemplos de preguntas para Claude:

- «Explícame qué hace el form CLIENTES.»
- «¿Qué forms se ven afectados si cambio la columna ESTADO de la tabla FACTURAS?»
- «¿Dónde se llama a PKG_FACTURAS.CALCULAR?»
- «Pasa la validación del WHEN-VALIDATE-ITEM de CLIENTES.NOMBRE a una validación de APEX.»

## Cómo funciona

1. **En Windows**, donde está Forms Builder, `windows/convertir.ps1` convierte los módulos a texto: los `.fmb`, `.mmb` y `.olb` a XML con `frmf2xml`, y las `.pll` a `.pld` con `frmcmp`.
2. **En la Mac** se copia esa carpeta y `forms_mcp.py` le da a Claude estas herramientas:

| Herramienta | Qué hace |
| --- | --- |
| `listar_modulos` | Todos los módulos, con sus bloques y cuánto código tienen |
| `ver_modulo` | Estructura de un módulo: bloques y su tabla, ítems y su columna, relaciones, LOVs, parámetros, librerías y la lista de triggers y program units |
| `ver_codigo` | El PL/SQL de un módulo, entero o de un trigger o program unit concreto |
| `buscar_codigo` | Busca un texto (o expresión regular) en el PL/SQL de todos los módulos |
| `uso_de_tabla` | Dónde se usa una tabla y, si se indica, una columna: bloques, ítems y código |
| `recargar` | Vuelve a leer la carpeta después de copiar XML nuevos |

Del XML solo se queda con lo que sirve para entender el módulo y todo su código. Las propiedades visuales (coordenadas, colores, fuentes), que son la mayor parte del XML, quedan fuera para no gastar el contexto de Claude.

## 1. Convertir los módulos (Windows)

Copia la carpeta `windows` a la PC con Forms Builder y, en PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File convertir.ps1 -Origen C:\ruta\a\los\forms
```

- Incluye las subcarpetas. Los originales no se tocan: se trabaja sobre una copia temporal.
- El resultado queda en `C:\ruta\a\los\forms\xml` (se puede cambiar con `-Destino`).
- El script busca `frmf2xml` y `frmcmp_batch` en la instalación de Oracle. Si no los encuentra, indícalos con `-Frmf2xml 'ruta\frmf2xml.bat'` y `-Frmcmp 'ruta\frmcmp_batch.cmd'`.
- Lo que dicen las herramientas de Oracle queda en `xml\conversion.log`.
- Si una `.pll` no se convierte, ábrela en Forms Builder y usa **Archivo › Convertir** para guardarla como `.pld` en la misma carpeta.

Vuelve a ejecutarlo cuando cambien los forms.

## 2. Copiar la carpeta a la Mac

Copia la carpeta `xml` a la Mac (OneDrive, Google Drive, un pendrive…), por ejemplo a `~/FormsXML`.

## 3. Instalar el servidor (Mac)

Necesita [uv](https://docs.astral.sh/uv/), que se encarga de Python y de la librería `mcp`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Para probarlo sin Claude (debe listar los módulos y quedarse esperando; sal con ⌃C):

```bash
uv run /ruta/a/FormsMCP/forms_mcp.py ~/FormsXML
```

## 4. Añadirlo a Claude Desktop

En Claude Desktop: **Ajustes › Desarrollador › Editar configuración**. Se abre `claude_desktop_config.json`; dentro de `"mcpServers"`, junto a la entrada de SQLcl, añade:

```json
"oracle-forms": {
  "command": "/Users/TU_USUARIO/.local/bin/uv",
  "args": ["run", "/Users/TU_USUARIO/ruta/a/FormsMCP/forms_mcp.py", "/Users/TU_USUARIO/FormsXML"]
}
```

Usa rutas completas (sin `~`). La ruta de `uv` la da `which uv`. Cierra Claude Desktop del todo (⌘Q) y vuelve a abrirlo: en el menú de herramientas del chat aparecerá **oracle-forms**.

## Sin el servidor

`resumir.py` genera un Markdown por módulo con su estructura y todo su código, para leerlo o pegarlo en una conversación:

```bash
python3 resumir.py ~/FormsXML ~/FormsResumen
```

## Archivos

- `forms_xml.py`: lee los XML y los `.pld` (solo biblioteca estándar de Python).
- `forms_mcp.py`: el servidor MCP. Usa la versión 1 de la librería `mcp`.
- `resumir.py`: el resumen en Markdown.
- `windows/convertir.ps1`: la conversión en Windows.
- `ejemplo/`: un formulario, un menú y una librería de ejemplo para probar.
