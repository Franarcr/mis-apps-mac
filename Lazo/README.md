# Lazo

Organizador de ventanas para macOS (14+), inspirado en Lasso. Es una app normal con ventana (aparece en el Dock, sin icono en la barra de menú) y necesita el permiso de **Accesibilidad** para mover las ventanas de otras apps.

## Cómo se usa

**Lo rápido (como Lasso):** pon el ratón sobre una ventana y pulsa **⌥⇧L** (Opción + Mayúsculas + L). Aparece la cuadrícula de cada monitor encima de la pantalla real: haz clic o arrastra sobre las celdas y la ventana se coloca ahí (Esc cancela). Si la ventana estaba en pantalla completa, Lazo la saca de ese modo antes de colocarla.

**La ventana de Lazo** (clic en el Dock o **⌃⌥⌘Espacio**) sirve para configurar la cuadrícula de cada monitor y colocar ventanas eligiéndolas de una lista (solo las del escritorio actual, no minimizadas):

1. Abre Lazo desde el Dock (o con ⌃⌥⌘Espacio) y elige arriba la ventana que quieres colocar.
2. Verás tus pantallas, cada una con su nombre, su fondo de escritorio y **su propia cuadrícula** (columnas × filas, ajustables encima de cada una y recordadas por monitor). La ventana actual aparece marcada con una línea discontinua.
3. **Arrastra sobre la cuadrícula de la pantalla donde la quieras**: la ventana se mueve a ese monitor, ocupa esa zona y Lazo se oculta.

## Distribuciones

En la barra lateral están las distribuciones guardadas (mitades, tercios, maximizar… y las tuyas):

- **Grabar**: pulsa *Grabar* y dibuja una zona en la cuadrícula; se guarda como distribución nueva. Haz clic en su nombre para cambiarlo.
- **Atajo**: pulsa el botón de la derecha y escribe la combinación (con ⌃, ⌥ o ⌘). Esc cancela y ⌫ lo quita.
- Doble clic aplica la distribución; clic derecho para quitar el atajo o eliminarla.
- Menú *Distribuciones*: importar, exportar (archivo `.json`) y restablecer las de serie.

## Acciones rápidas

| Atajo | Acción |
| --- | --- |
| ⌥⇧L | Cuadrícula sobre la pantalla para la ventana bajo el ratón (se puede cambiar en la ventana de Lazo) |
| ⌃⌥⌘Espacio | Abrir la ventana de Lazo |
| ⌃⌥← / ⌃⌥→ / ⌃⌥↑ / ⌃⌥↓ | Mitades (distribuciones de serie) |
| ⌃⌥↩ | Maximizar |
| ⌃⌥1 / 2 / 3 / 4 | Tercios y dos tercios |
| ⌃⌥C | Centrar |
| ⌃⌥⌫ | Restaurar el tamaño anterior |
| ⌃⌥⌘→ / ⌃⌥⌘← | Siguiente / anterior pantalla |
| ⌃⌥ + arrastrar | Mover cualquier ventana desde cualquier punto (con ⇧, cambiar su tamaño) |

Abajo se ajustan la separación entre ventanas y si los atajos colocan la ventana activa o la que está bajo el ratón. Al cerrar la ventana, Lazo sigue funcionando en segundo plano para que los atajos respondan.

## Compilar

```bash
./build.sh                                         # compila e instala en /Applications
.build/release/Lazo --snapshot ventana.png          # imagen de la ventana con datos de ejemplo
```
