# Batido — contexto

App del Mac (`com.fran.batido`): **editor de páginas web con vista previa en vivo** (HTML, CSS, JS y PHP), 670cae0.
Lee `../CLAUDE.md` (reglas generales).

## Partes

- **`CodeEditor.swift`:** editor sobre NSTextView. Tiene números de línea, sangría automática y barra de búsqueda.
- **`Highlighter.swift`:** colorea con expresiones regulares, sin dependencias.
  - Cadenas y comentarios en una sola pasada.
  - Reconoce CSS dentro de `<style>`, JS dentro de `<script>` y bloques PHP.
- **`Preview.swift`:** vista previa en WKWebView.
  - Añade `<base>` para que las rutas relativas funcionen.
  - Ejecuta PHP con el binario del Mac (Homebrew o una ruta propia).
  - Puede dibujar la página con un ancho de escritorio aunque el panel sea estrecho.
- **`Validator.swift`:** revisión sencilla. Avisa de etiquetas sin cerrar, llaves descompensadas, ids duplicados
  e imágenes sin alt. Los errores llevan línea y columna.
- **`Snippets.swift`:** fragmentos de fábrica más los que crea Fran, guardados en preferencias.
  - `${caret}` marca dónde queda el cursor.
  - Cada fragmento puede tener su atajo.
- **`DocModel.swift`:** estado de cada ventana (modo, archivos vinculados, problemas y consola).
- **`Inspector.swift`:** panel lateral.

## Compilar

`./build.sh` → `/Applications/Batido.app`.
