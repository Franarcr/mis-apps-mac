# Investigación: Things 3 y propuesta de una app parecida

Fecha: 10 de noviembre de 2026.

## 1. Qué es Things 3

Things 3 es una app de tareas personales de la empresa alemana Cultured Code. Funciona en Mac, iPhone, iPad, Apple Watch y Vision Pro, y ganó dos premios de diseño de Apple. Su fama viene de tres cosas: es muy sencilla, es bonita y se usa rápido. No es para equipos: es para una sola persona.

Su idea central es que **no importa tanto *qué* tienes que hacer, sino *cuándo* piensas empezarlo.**

## 2. Cómo se organiza

### Las listas fijas (barra lateral)

| Lista | Qué contiene |
|---|---|
| **Entrada** (Inbox) | Todo lo que anotas rápido sin decidir nada. Sale de aquí apenas le pones fecha o lo metes en un proyecto. |
| **Hoy** | Lo que te comprometes a hacer hoy. Abajo tiene una sección **Esta noche** para lo de después del trabajo. Arriba muestra los eventos del calendario. |
| **Próximo** (Upcoming) | Una línea de tiempo: los próximos 7 días uno por uno, luego por semanas y luego por meses. Muestra tareas con fecha, fechas límite, tareas que se repiten y eventos del calendario. |
| **Cuando sea** (Anytime) | Todo lo que puedes hacer ya, sin fecha concreta. Incluye lo de Hoy. |
| **Algún día** (Someday) | Ideas o cosas en pausa. Quedan escondidas del resto de listas para que no estorben. |
| **Registro** (Logbook) | Archivo de todo lo terminado, ordenado por fecha. |
| **Papelera** | Lo borrado, recuperable. |

Entre *Próximo*, *Cuando sea* y *Algún día* una tarea solo puede estar en una a la vez.

### Las piezas para agrupar

- **Áreas**: partes de tu vida que nunca terminan (Familia, Trabajo, Salud, Dinero). Contienen proyectos y tareas sueltas.
- **Proyectos**: algo que tiene final y varios pasos. Muestran un **circulito de progreso** que se va llenando.
- **Encabezados**: dividen un proyecto grande en secciones (ej. «Compras», «Papeleo»).
- **Tareas**: lo básico.
- **Lista de pasos** dentro de una tarea (checklist): pasos chiquitos que no merecen ser tareas propias.
- **Etiquetas**: para filtrar (ej. «llamadas», «compras», «10 min»). Pueden estar anidadas.

### Lo que lleva cada tarea

Título · notas (con formato) · **cuándo** (hoy, esta noche, una fecha o algún día) · **fecha límite** (distinta de «cuándo»: es el día en que *tiene* que estar) · recordatorio con hora · etiquetas · lista de pasos · a qué proyecto/área/encabezado pertenece · repetición · completada o cancelada.

La diferencia entre **cuándo** y **fecha límite** es clave: «cuándo» dice qué día aparece en *Hoy*; la fecha límite solo avisa (en rojo) que se acaba el plazo.

### Tareas que se repiten

Dos tipos:
1. **Calendario fijo**: «todos los lunes», «el 1 de cada mes».
2. **Después de completarla**: «3 días después de que la termine» (ej. regar las plantas).

Desde agosto de 2026 (versión 3.23) se pueden completar antes de tiempo, y al moverlas te pregunta si cambias solo esa vez o la regla entera.

## 3. Cómo se siente al usarla

- **Botón + mágico**: el botón de agregar se puede **arrastrar** al lugar exacto de la lista donde quieres la tarea nueva, a un día de *Próximo* o a la *Entrada*.
- **Tarjeta que se abre**: al tocar una tarea, se levanta como una tarjeta con todos sus detalles; el resto se desvanece. Los campos que no usas quedan escondidos detrás de iconitos.
- **Gestos**: deslizar a la derecha para cambiar la fecha; a la izquierda para seleccionar varias; mantener presionado para arrastrar y reordenar.
- **Selector «¿Cuándo?»**: un menú con Hoy, Esta noche, un calendario, Algún día, y un campo donde escribes «mañana», «viernes», «en 3 días» y lo entiende.
- **Búsqueda rápida**: tirar hacia abajo en cualquier pantalla abre la búsqueda (tareas, proyectos, etiquetas y el Registro).
- **Rutina diaria**: cada mañana revisas la Entrada y Hoy, decides, pospones lo demás y ordenas.
- **Estilo visual**: mucho espacio en blanco, letra en negrita, poco color, animaciones suaves. Modo oscuro.

## 4. Extras

Widgets en la pantalla de inicio y de bloqueo · Siri y Atajos · app del Apple Watch · eventos del calendario dentro de Hoy · recordatorios con notificación · enviar correos para que se vuelvan tareas · enlaces `things:///` para que otras apps creen tareas · sincronización entre aparatos (Things Cloud).

## 5. Propuesta: «Hecho» (nombre provisional)

Una app propia para tu iPhone, en español, con la misma forma de trabajar pero con **nombre, diseño y colores nuestros** (no una copia de Things). Mismo método de trabajo que Vital: Xcode, se instala con un script en «Francho».

### Etapa 1 — Lo esencial (la que haría primero)
- Las 7 listas: Entrada, Hoy (con Esta noche), Próximo, Cuando sea, Algún día, Registro, Papelera.
- Áreas, proyectos con circulito de progreso, encabezados.
- Tareas con notas, cuándo, fecha límite, lista de pasos y etiquetas.
- Tarjeta que se abre al tocar, selector «¿Cuándo?» que entiende «mañana», «viernes», «en 3 días».
- Gestos: deslizar para fecha, arrastrar para ordenar.
- Búsqueda tirando hacia abajo.
- Modo claro y oscuro. Los datos se guardan en el iPhone.

### Etapa 2 — Lo que la vuelve útil todos los días
- Recordatorios con hora (notificaciones).
- Tareas que se repiten (los dos tipos).
- Eventos de tu calendario dentro de Hoy y Próximo.
- Widget con las tareas de Hoy.
- Botón + que se arrastra.

### Etapa 3 — Opcional
- Sincronizar con iCloud (para Mac/iPad).
- Siri y Atajos, app del Apple Watch.

### Detalles a tener en cuenta
- Como tu cuenta de desarrollador es gratuita, la app caduca a los 7 días y hay que reinstalarla con el script (igual que Vital). La sincronización con iCloud de la etapa 3 necesita cuenta de pago.
- Los datos quedarían solo en el iPhone hasta la etapa 3.

## Fuentes
- [Things — sitio oficial](https://culturedcode.com/things/)
- [Guía «Getting Productive with Things»](https://culturedcode.com/things/guide/)
- [Funciones de Things 3](https://culturedcode.com/things/features/)
- [Esquema de enlaces de Things (modelo de datos)](https://culturedcode.com/things/support/articles/2803573/)
- [Reseña de MacStories](https://www.macstories.net/reviews/things-3-beauty-and-delight-in-a-task-manager/)
- [Repeating To-Dos, Refined (agosto 2026)](https://culturedcode.com/things/blog/2026/08/repeating-to-dos-refined/)
- [MacRumors: Things 3.23](https://macrumors.com/2026/08/19/things-3-23-brings-long-requested-overhaul-of-repeating-to-dos)
- [Wikipedia: Things (software)](https://en.wikipedia.org/wiki/Things_(software))
