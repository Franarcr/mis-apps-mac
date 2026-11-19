# Lienzo — contexto

App del Mac (`com.fran.lienzo`): una **pizarra infinita** al estilo Miro, que además importa tableros de Miro
(e4cca45). Lee `../CLAUDE.md` (reglas generales).

## Cómo funciona

- **Documento:** cada tablero es un archivo `.lienzo` (JSON con las imágenes dentro) y tiene deshacer
  (`BoardDocument.swift`). Al guardar solo se incluyen las imágenes que se usan.
- **Pizarra:** `CanvasView.swift` dibuja y atiende ratón, trackpad y teclado (zoom; con Mayúsculas el ratón
  desplaza de lado). `Renderer.swift` dibuja los elementos; los títulos de los marcos van encima de todo.
- **Elementos y herramientas** (`Model.swift`): notas, texto, figuras, flechas, lápiz, marcos, comentarios e
  imágenes. Cada herramienta tiene su tecla. Coordenadas en puntos del tablero, con el eje Y hacia abajo.
- **Barras flotantes** encima del lienzo, claras como el papel (`BoardWindow.swift`).
- **Ventana de inicio** con los tableros recientes (`Welcome.swift`).

## Importar de Miro

`MiroImport.swift` usa la API pública de Miro (solo lectura). Acepta un enlace, un id suelto o el HTML guardado
desde Miro: «Abrir…» también acepta ese HTML (`DocumentController.swift`). Para pruebas se puede apuntar a otro
servidor con la variable `LIENZO_MIRO_API`.

## Compilar

`./build.sh` → `/Applications/Lienzo.app`.
