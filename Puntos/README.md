# Puntos

Bloc de notas para macOS (14+) inspirado en Tot: **7 notas**, cada una con su punto de color.

- El punto aparece **relleno** si la nota tiene texto, y con un **anillo** si es la nota abierta.
- **Markdown en vivo**: `#` títulos, `**negrita**`, `*cursiva*`, `` `código` ``, `~~tachado~~`, listas, `> citas` y casillas `- [ ]` / `- [x]`. Los enlaces se pueden pulsar.
- Al pulsar Intro en una lista, la viñeta (o el número) continúa sola; en una línea de lista vacía, se quita.
- Contador de palabras y caracteres, y botón para copiar toda la nota.
- Como Tot, la ventana **no se minimiza** y **desaparece al pasar a otra app**; vuelve con ⌥⇧N o desde la barra de menú.
- Las notas se guardan solas en `~/Library/Application Support/Puntos/Nota 1.md` … `Nota 7.md`.

| Atajo | Acción |
| --- | --- |
| ⌥⇧N | Mostrar u ocultar la ventana (desde cualquier app) |
| ⌘1 – ⌘7 | Cambiar de nota |
| ⌘B / ⌘I / ⇧⌘X / ⌘K | Negrita / cursiva / tachado / código |
| ⌘F, ⌘G | Buscar, buscar siguiente |
| ⌘+ / ⌘− | Tamaño de letra |
| ⇧⌘C | Copiar toda la nota |
| ⌘W | Cerrar la ventana (la app sigue en la barra de menú) |

Un **clic** en el icono de la barra de menú abre la ventana justo debajo (como Tot); con **clic derecho** aparece el menú, con la primera línea de cada nota y las opciones para abrir la app al iniciar sesión o **mantener la ventana visible** (fija y encima de las demás).

## Compilar

```bash
./build.sh    # compila e instala en /Applications
```

Para revisar el diseño sin abrir la app: `/Applications/Puntos.app/Contents/MacOS/Puntos --snapshot imagen.png`
