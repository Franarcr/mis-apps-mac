# Mis apps para Mac

Apps para macOS con chip Apple, escritas en Swift sin Xcode (solo con las Command Line Tools). Casi todas viven en la barra de menú; Historietas, Compresor, Lazo, Grabador y Revela tienen ventana y viven en el Dock.

| App | Qué hace | macOS |
| --- | --- | --- |
| [Captura](Captura/) | Capturas de pantalla completa o de área con anotaciones (flechas, cuadros, texto), OCR, vídeo con audio, GIF y capturas largas con desplazamiento (al estilo de CleanShot) | 15+ |
| [Portapapeles](Portapapeles/) | Historial de las últimas 100 copias, con buscador (⌥⇧V), y pegar sin formato (⌥⇧⌘V) | 14+ |
| [Puntos](Puntos/) | Bloc de 7 notas con Markdown en vivo, al estilo de Tot (⌥⇧N) | 14+ |
| [Monitor](Monitor/) | Widget de escritorio con CPU, memoria, GPU, temperatura, consumo, red, disco, batería y procesos en tiempo real | 14+ |
| [Ventanas](Ventanas/) | El botón verde agranda la ventana sin pantalla completa, y el rojo cierra del todo las apps que elijas | 14+ |
| [Volumen](Volumen/) | Volumen de cada app por separado, de silencio a 150 % | 14.2+ |
| [Compresor](Compresor/) | Abrir, extraer y crear comprimidos (ZIP con AES-256, 7z, RAR 4/5, TAR…), con Servicios del Finder, al estilo de WinZip | 14+ |
| [Lazo](Lazo/) | Colocar ventanas con la cuadrícula de cada monitor (⌥⇧L sobre la ventana), zonas con atajo y arrastre con ⌃⌥, al estilo de Lasso | 14+ |
| [Grabador](Grabador/) | Grabar imágenes de sistemas (.img, .iso, .zip, .xz…) en USB y tarjetas SD con verificación, al estilo de balenaEtcher | 14+ |
| [Revela](Revela/) | Editor de fotos (también RAW) con ajustes, looks, LUT .cube y la IA de macOS: desenfocar fondo, luz del sujeto, enderezar horizonte. Inspirado en Luminar | 14+ |
| [Barra](Barra/) | Junta en un solo icono las demás apps: las desmarcadas esconden su icono y siguen funcionando | 14+ |
| [Historietas](Historietas/) | Lector de cómics CBZ, CBR, CB7 y CBT, con doble página, lectura de manga y la página por la que ibas | 14+ |

Para instalarlas desde los `.zip` de *Releases*, sigue [INSTALAR.md](INSTALAR.md).

## Vital (iPhone)

[Vital](Vital/) es una app de iPhone (iOS 18+) al estilo de Bevel, con los datos del Apple Watch y de la báscula que llegan a Salud. Todo se calcula en el teléfono; solo la búsqueda por código de barras usa internet.

- **Salud:** recuperación diaria frente a tu propia base (VFC, pulso en reposo, sueño, temperatura, respiración, SpO₂), estrés y energía del día, sueño con regularidad y deuda, avisos del reloj y consejo del día. Todo en semáforo, con historial de 30 días.
- **Entreno:** esfuerzo del día frente al objetivo según la recuperación, carga semanal, VO₂ máx., recuperación cardiaca y entrenamientos con zonas de pulso.
- **Rutinas:** 876 ejercicios en español ([free-exercise-db](https://github.com/yuhonas/free-exercise-db), dominio público) filtrables por músculo y equipo, ejercicios propios, pirámide 12-10-8-6 y cargas que se estiman por tu perfil y se ajustan con lo que anotas.
- **Cuerpo:** peso, grasa, masa magra e IMC de la báscula (Fitdays) vía Salud, y el resto del informe (grasa visceral, agua, músculo, hueso, metabolismo basal, edad corporal…) leído de una captura.
- **Comida:** calorías y macros del día según tu metabolismo basal, la energía activa del reloj y tu objetivo. Comida tica con valores aproximados, código de barras (Open Food Facts, solo se envía el código), foto de la etiqueta leída en el teléfono y comidas a mano. Cada producto se califica en semáforo por azúcares, sodio, grasas y aditivos.

- **Ayuno** (pestaña propia, con Hoy, Progreso y Plan): temporizador con fases estimadas y planes 12:12 a 18:6 que se cierra solo al registrar comida, con racha, regularidad, historial y avisos. Lo cruza con tu sueño y VFC, la recuperación y el entreno, la proteína de la ventana, el peso y la glucosa si tienes sensor. Fuera de la app: Actividad en vivo en la pantalla bloqueada y la Dynamic Island, widgets de inicio y de pantalla bloqueada con botón para empezar o terminar, y Siri («Empezar ayuno en Vital», «Cuánto llevo de ayuno en Vital»). Los días sin ayuno, «Comer menos»: un reto de 5–15 % por debajo de lo que sueles comer (nunca bajo tu metabolismo basal), hora de cerrar la cocina con aviso, cuántas veces picaste de noche y una idea práctica cada día.

Necesita Xcode. Con el iPhone emparejado con el Mac, por cable o por Wi-Fi (desbloqueado y con el Modo desarrollador activado), este script la compila, la instala y la abre:

```bash
cd Vital && ./instalar-iphone.sh
```

Opciones: `--ayuno-demo` carga una semana de ayunos de ejemplo, `--borrar-demo` los borra y `--demo` usa datos inventados en vez de Salud. En `Vital.xcodeproj` cambia `DEVELOPMENT_TEAM` por tu equipo si no es el tuyo.

## Compilar

Una sola vez, crea el certificado de firma local para que macOS conserve los permisos al recompilar:

```bash
./crear-firma.sh
```

Después, cada app se compila e instala en `/Applications` con su script:

```bash
cd Captura && ./build.sh
```

Para generar los `.zip` y las instrucciones en `dist/`:

```bash
./empaquetar.sh
```

Los iconos se generan con [iconos/crear-icono.swift](iconos/crear-icono.swift).

## Otras herramientas

- [FormsMCP](FormsMCP/): servidor MCP para que Claude Desktop lea los formularios, menús y librerías de Oracle Forms (convertidos con `frmf2xml`), junto al SQLcl MCP.
