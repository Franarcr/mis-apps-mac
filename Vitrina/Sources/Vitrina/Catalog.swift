import Foundation

/// Lo que Vitrina sabe de cada app casera: para qué sirve, dónde vive y qué permisos pide.
struct AppInfo: Identifiable, Hashable {
    enum Kind { case menuBar, window }

    let name: String
    let bundleID: String
    let summary: String
    let kind: Kind
    /// Aviso que se muestra después de instalarla (nil si no necesita nada).
    var setup: Setup? = nil

    var id: String { name }
}

/// Lo que hay que hacer después de instalar una app.
struct Setup: Hashable {
    let text: String
    var buttonTitle: String? = nil
    var settingsURL: String? = nil
}

private let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
private let screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

enum Catalog {
    static let apps: [AppInfo] = [
        AppInfo(name: "Captura", bundleID: "com.fran.captura",
                summary: "Capturas con flechas y texto, OCR, vídeo y GIF", kind: .menuBar,
                setup: Setup(text: "Necesita permiso de Grabación de pantalla. Actívalo, sal de Captura desde su icono y vuelve a abrirla.",
                             buttonTitle: "Abrir Grabación de pantalla", settingsURL: screenRecording)),
        AppInfo(name: "Portapapeles", bundleID: "com.fran.portapapeles",
                summary: "Guarda lo último que copias y pega sin formato", kind: .menuBar,
                setup: Setup(text: "Para que Enter pegue directamente, en su menú elige «Activar pegado automático…» y da permiso de Accesibilidad.",
                             buttonTitle: "Abrir Accesibilidad", settingsURL: accessibility)),
        AppInfo(name: "Puntos", bundleID: "com.fran.puntos",
                summary: "Bloc de 7 notas de colores (⌥⇧N)", kind: .menuBar),
        AppInfo(name: "Monitor", bundleID: "com.fran.monitor",
                summary: "Widgets de CPU, memoria, red, disco y batería", kind: .menuBar,
                setup: Setup(text: "Los widgets se agregan desde el escritorio: clic derecho › Editar widgets, y busca Monitor.")),
        AppInfo(name: "Ventanas", bundleID: "com.fran.ventanas",
                summary: "El botón verde agranda y el rojo cierra del todo", kind: .menuBar,
                setup: Setup(text: "Necesita permiso de Accesibilidad para mover y cerrar las ventanas de otras apps.",
                             buttonTitle: "Abrir Accesibilidad", settingsURL: accessibility)),
        AppInfo(name: "Volumen", bundleID: "com.fran.volumen",
                summary: "Volumen de cada app por separado", kind: .menuBar,
                setup: Setup(text: "La primera vez que cambies un volumen pedirá permiso para grabar el audio del sistema. Lo necesita para cambiarlo; no graba nada.")),
        AppInfo(name: "Oido", bundleID: "com.fran.oido",
                summary: "Graba y pasa a texto tus llamadas de WhatsApp, Teams y Meet", kind: .menuBar,
                setup: Setup(text: "La primera vez pide permiso de Micrófono y de audio del sistema. El resumen necesita Apple Intelligence (macOS 26). Recuerda avisar cuando grabes una llamada.")),
        AppInfo(name: "Barra", bundleID: "com.fran.barra",
                summary: "Junta en un solo icono las demás apps", kind: .menuBar),
        AppInfo(name: "Barrendero", bundleID: "com.fran.barrendero",
                summary: "Limpia el correo de Mail cada semana", kind: .menuBar,
                setup: Setup(text: "La primera vez que revise el correo, macOS preguntará si puede controlar Mail. Pulsa Permitir.")),
        AppInfo(name: "Guardian", bundleID: "com.fran.guardian",
                summary: "Vigila AnyDesk y revisa los programas instalados", kind: .menuBar),
        AppInfo(name: "Hecho", bundleID: "com.francho.hecho",
                summary: "Tareas y proyectos, se sincroniza con el iPhone", kind: .window,
                setup: Setup(text: "Para sincronizar con el iPhone por Wi-Fi, permite el acceso a la red local cuando macOS lo pregunte.")),
        AppInfo(name: "Lienzo", bundleID: "com.fran.lienzo",
                summary: "Pizarra infinita para ideas y tableros", kind: .window),
        AppInfo(name: "Revela", bundleID: "com.fran.revela",
                summary: "Edita fotos, también RAW", kind: .window),
        AppInfo(name: "Historietas", bundleID: "com.fran.historietas",
                summary: "Lee cómics y manga (CBZ, CBR, CB7…)", kind: .window),
        AppInfo(name: "Compresor", bundleID: "com.fran.compresor",
                summary: "Abre y crea ZIP, 7z, RAR, TAR…", kind: .window,
                setup: Setup(text: "Sus opciones aparecen en el clic derecho del Finder. Si no salen, búscalas en el submenú Servicios.")),
        AppInfo(name: "Lazo", bundleID: "com.fran.lazo",
                summary: "Coloca ventanas en una cuadrícula (⌥⇧L)", kind: .window,
                setup: Setup(text: "Necesita permiso de Accesibilidad para mover las ventanas de otras apps.",
                             buttonTitle: "Abrir Accesibilidad", settingsURL: accessibility)),
        AppInfo(name: "Grabador", bundleID: "com.fran.grabador",
                summary: "Graba imágenes de sistemas en USB y tarjetas SD", kind: .window,
                setup: Setup(text: "Al grabar, macOS pedirá tu contraseña de administrador para escribir en el USB o la tarjeta.")),
        AppInfo(name: "Batido", bundleID: "com.fran.batido",
                summary: "Escribe páginas web y míralas al momento", kind: .window),
        AppInfo(name: "Antena", bundleID: "com.fran.antena",
                summary: "Redes Wi-Fi cercanas, sus canales y su señal", kind: .window,
                setup: Setup(text: "Para ver los nombres de las redes, permite la Localización cuando macOS lo pregunte.")),
        AppInfo(name: "MacCleaner", bundleID: "local.elena.maccleaner",
                summary: "Limpieza, desinstalador, archivos grandes y mantenimiento", kind: .window,
                setup: Setup(text: "Para revisar todo el disco necesita Acceso total al disco: pulsa +, elige MacCleaner en Aplicaciones y vuelve a abrirla. Sin ese permiso funciona, pero revisa menos.",
                             buttonTitle: "Abrir Acceso total al disco",
                             settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")),
        AppInfo(name: "Suite Notarial", bundleID: "local.elena.suitenotarial",
                summary: "Plazos, expedientes, protocolo, cobros y facturas del despacho", kind: .window,
                setup: Setup(text: "La primera vez que lea el correo, macOS preguntará si puede usar Mail. Pulsa Permitir. Sus datos quedan solo en esa Mac.")),
    ]
}
