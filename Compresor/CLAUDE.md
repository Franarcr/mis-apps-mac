# Compresor — contexto

App del Mac (`com.fran.compresor`, macOS 14+): **comprime y extrae archivos**, al estilo WinZip y Archiver
(7c9bcac). Lee `../CLAUDE.md` (reglas generales) y `README.md` (qué hace, para Fran).

## Cómo funciona

- **Motor:** la libarchive que trae macOS (`/usr/lib/libarchive.2.dylib`), sin bibliotecas de terceros. macOS no
  trae sus cabeceras, así que `Sources/CArchive/include/CArchive.h` declara a mano solo las funciones que se usan;
  si hace falta otra, se agrega ahí.
- **`ArchiveEngine.swift`:** listar, extraer (todo o lo seleccionado), crear y detectar los RAR divididos en partes
  (`volumes(of:)`). Crea ZIP (con AES-256 opcional), 7z, TAR.GZ y TAR.XZ (`CreateFormat`). Al extraer descarta
  rutas con `..` o absolutas (`safeRelativePath`) y nunca sobrescribe (`uniqueURL`).
- **`ArchiveActions.swift`:** «Extraer aquí» inteligente (una sola carpeta → tal cual; varios sueltos → los agrupa
  en una carpeta) y «Comprimir».
- **`Operations.swift`:** corre el trabajo en segundo plano con barra de progreso y cancelar, muestra los errores y
  pide la contraseña (vuelve a pedirla si es incorrecta).
- **Ventanas:** `ArchiveWindow.swift` lista el contenido con buscador, vista rápida (⌘Y) y doble clic para abrir;
  `CreateWindow.swift` elige formato, contraseña y carpeta. `AppDelegate.swift` arma el menú y decide qué hacer con
  lo que se suelta en la ventana o en el Dock (los comprimidos se abren, el resto se comprime).
- **Servicios del Finder** (clic derecho), declarados en `Resources/Info.plist` (`NSServices`) y atendidos en
  `ServiceProvider.swift`: *Comprimir con Compresor*, *Comprimir con Compresor…* y *Extraer aquí con Compresor*.
  Cuando la app se abre por un servicio no se cierra al cerrar la última ventana.

## Límites conocidos

- **RAR:** se abre y extrae (RAR 4 y 5, también en partes), pero no se crea (formato propietario).
- **RAR con contraseña:** la libarchive de macOS no admite su cifrado; la app lo avisa en lugar de fallar en
  silencio.

## Compilar y probar

- `./build.sh` → `/Applications/Compresor.app`.
- `.build/release/Compresor --self-test` crea, lista y extrae en todos los formatos, con y sin contraseña, y prueba
  las rutas peligrosas. Correrlo después de tocar el motor.
- Sin interfaz: `--list`, `--extract`, `--compress` y `--volumes` (ver `main.swift`).
- Ojo: el self-test usa datos aleatorios, así que sus tamaños parecen «sin comprimir». Para comprobar la compresión,
  usar un texto (el 19-11-2026 un texto de 729 KB quedó en 50 KB en ZIP y en 9 KB en TAR.XZ).
