import AppKit
import SwiftUI
import WebKit

/// Prepara la página que se muestra según el modo.
enum PreviewBuilder {
    static func page(for text: String, lang: Lang) -> String {
        switch lang {
        case .html, .php:
            return text
        case .css:
            return """
            <!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><style>\(text)</style></head>
            <body>
            <header><nav><a href="#">Inicio</a> · <a href="#">Productos</a> · <a href="#">Contacto</a></nav></header>
            <main>
            <h1>Título principal</h1>
            <h2>Subtítulo</h2>
            <p>Este es un párrafo de muestra con <a href="#">un enlace</a>, texto en <strong>negrita</strong> y en <em>cursiva</em>. Así ves cómo queda tu hoja de estilo.</p>
            <blockquote>Una cita destacada para probar estilos.</blockquote>
            <ul><li>Primer elemento</li><li>Segundo elemento</li><li>Tercer elemento</li></ul>
            <table><tr><th>Nombre</th><th>Precio</th></tr><tr><td>Café</td><td>₡1 500</td></tr><tr><td>Batido</td><td>₡2 200</td></tr></table>
            <form><label>Correo <input type="email" placeholder="tu@correo.com"></label> <button type="button">Enviar</button></form>
            <div class="caja">Un div con la clase «caja»</div>
            </main>
            <footer><small>Pie de página</small></footer>
            </body></html>
            """
        case .js:
            // El código empieza en la línea 1 para que los errores coincidan con el editor.
            return "<!DOCTYPE html><meta charset=\"utf-8\"><body style=\"font:13px -apple-system,sans-serif;color:#888;margin:2rem\">"
                + "<script>" + text + "\n</script><div id=\"batido-aviso\">Lo que escribas con console.log aparece en la pestaña Consola.</div></body>"
        }
    }

    /// Añade <base> para que las rutas relativas (CSS, imágenes) apunten a la carpeta del archivo.
    static func addBase(_ dir: URL, to html: String) -> String {
        let ns = html as NSString
        if ns.range(of: "<base", options: .caseInsensitive).location != NSNotFound { return html }
        let tag = "<base href=\"\(dir.absoluteString)\">"
        let head = Highlighter.re(#"<head(?:\s[^>]*)?>"#)
        if let m = head.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
            return ns.replacingCharacters(in: NSRange(location: NSMaxRange(m.range), length: 0), with: tag)
        }
        return tag + html
    }
}

/// Ejecuta PHP con el binario instalado en el Mac (Homebrew o ruta propia).
enum PHPRunner {
    struct Output {
        var html: String
        var text: String
        var problems: [Problem]
    }

    static func find(customPath: String) -> URL? {
        let candidates = [customPath, "/opt/homebrew/bin/php", "/usr/local/bin/php", "/usr/bin/php"]
        for p in candidates where !p.isEmpty && FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    static func run(_ code: String, workingDirectory: URL?, customPath: String) -> Output {
        guard let php = find(customPath: customPath) else {
            let msg = """
            <!DOCTYPE html><meta charset="utf-8"><body style="font:15px -apple-system,sans-serif;margin:3rem;color:#444">
            <h2>Falta PHP en este Mac</h2>
            <p>Para ver páginas PHP, instala PHP con Homebrew escribiendo en Terminal:</p>
            <pre style="background:#f3f3f3;padding:1rem;border-radius:8px">brew install php</pre>
            <p>Si ya lo tienes en otro sitio, indica la ruta en Batido ▸ Ajustes.</p></body>
            """
            return Output(html: msg, text: "No se encontró el programa php.", problems: [])
        }
        let p = Process()
        p.executableURL = php
        p.arguments = ["-d", "display_errors=stdout", "-d", "html_errors=0", "-d", "error_reporting=E_ALL"]
        if let workingDirectory { p.currentDirectoryURL = workingDirectory }
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        do { try p.run() } catch {
            return Output(html: "No se pudo ejecutar PHP: \(error.localizedDescription)", text: "\(error)", problems: [])
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        input.fileHandleForWriting.write(Data(code.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        let text = String(decoding: data, as: UTF8.self)

        var problems: [Problem] = []
        let re = Highlighter.re(#"(?:PHP )?(Parse error|Fatal error|Warning|Notice|Deprecated): (.+?) in .+? on line (\d+)"#)
        let ns = text as NSString
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let kind = ns.substring(with: m.range(at: 1))
            let msg = ns.substring(with: m.range(at: 2))
            let line = Int(ns.substring(with: m.range(at: 3))) ?? 0
            let isError = kind.contains("error")
            problems.append(Problem(kind: isError ? .error : .warning, message: "PHP: \(msg)", line: line, column: 1, source: "PHP"))
        }
        return Output(html: text, text: text, problems: problems)
    }
}

/// Puente débil para que WebKit no retenga al anfitrión (evita ciclos de memoria).
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// WKWebView que avisa cuando cambia de ancho (para ajustar el ancho de página).
final class ResizingWebView: WKWebView {
    var onResize: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onResize?() }
    }
}

/// Un WKWebView con su lógica: conserva el desplazamiento al recargar y recoge la consola.
final class PreviewHost: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: ResizingWebView
    weak var model: DocModel?
    private var pendingScroll: (Double, Double)?

    static let consoleScript = """
    (function(){
      function send(t, args, line){
        try {
          var m = Array.prototype.map.call(args, function(x){
            if (x instanceof Error) return x.message;
            if (typeof x === 'object') { try { return JSON.stringify(x); } catch(e) { return String(x); } }
            return String(x);
          }).join(' ');
          window.webkit.messageHandlers.batido.postMessage({t: t, m: m, l: line || 0});
        } catch(e) {}
      }
      ['log','info','warn','error','debug'].forEach(function(k){
        var o = console[k];
        console[k] = function(){ send(k, arguments); o.apply(console, arguments); };
      });
      window.addEventListener('error', function(e){
        if (e.message) send('error', [e.message], e.lineno);
      });
      window.addEventListener('unhandledrejection', function(e){
        send('error', ['Promesa rechazada: ' + e.reason]);
      });
      // Los enlaces a secciones (#accesos) bajan dentro de la página en vez de abrir la carpeta.
      document.addEventListener('click', function(e){
        if (e.defaultPrevented || e.button !== 0) return;
        var a = e.target.closest ? e.target.closest('a[href]') : null;
        if (!a) return;
        var h = a.getAttribute('href');
        if (!h || h.charAt(0) !== '#') return;
        e.preventDefault();
        if (h === '#' || h === '#top') { window.scrollTo({top: 0, behavior: 'smooth'}); return; }
        var id = decodeURIComponent(h.slice(1));
        var el = document.getElementById(id) || document.getElementsByName(id)[0];
        if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
      });
    })();
    """

    init(model: DocModel) {
        self.model = model
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller
        webView = ResizingWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        super.init()
        controller.add(WeakMessageHandler(self), name: "batido")
        webView.navigationDelegate = self
        webView.onResize = { [weak self] in self?.applyZoom() }
    }

    func applyZoom() {
        guard let model else { return }
        let z = MainActor.assumeIsolated { model.effectiveZoom(paneWidth: Double(webView.bounds.width)) }
        if abs(webView.pageZoom - z) > 0.001 { webView.pageZoom = z }
    }

    func load(_ url: URL, readAccess: URL) {
        webView.evaluateJavaScript("[window.scrollX, window.scrollY]") { [weak self] result, _ in
            guard let self else { return }
            if let a = result as? [Double], a.count == 2 { self.pendingScroll = (a[0], a[1]) }
            self.webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let (x, y) = pendingScroll {
            webView.evaluateJavaScript("window.scrollTo(\(x), \(y))")
            pendingScroll = nil
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Los enlaces a internet se abren en el navegador; la vista previa se queda con tu página.
        if action.navigationType == .linkActivated, let url = action.request.url, url.isFileURL, url.hasDirectoryPath {
            decisionHandler(.cancel)
            return
        }
        if action.navigationType == .linkActivated, let url = action.request.url,
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let kind = body["t"] as? String ?? "log"
        let text = body["m"] as? String ?? ""
        let line = body["l"] as? Int
        Task { @MainActor in
            self.model?.receive(kind: kind, message: text, line: (line ?? 0) > 0 ? line : nil)
        }
    }

    func tearDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "batido")
    }
}

struct PreviewView: NSViewRepresentable {
    @ObservedObject var model: DocModel

    func makeCoordinator() -> PreviewHost { PreviewHost(model: model) }

    func makeNSView(context: Context) -> ResizingWebView {
        let host = context.coordinator
        model.register(host)
        return host.webView
    }

    func updateNSView(_ nsView: ResizingWebView, context: Context) {
        context.coordinator.applyZoom()
    }

    static func dismantleNSView(_ nsView: ResizingWebView, coordinator: PreviewHost) {
        coordinator.tearDown()
    }
}
