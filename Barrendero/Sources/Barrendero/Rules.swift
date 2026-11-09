import Foundation

/// Correos de un remitente que solo se barren si el asunto también coincide
/// (p. ej. los avisos de inicio de sesión del BN, pero no sus comprobantes).
struct SubjectRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var sender: String
    var subject: String
}

/// Qué barre Barrendero. Se guarda en ~/Library/Application Support/Barrendero/reglas.json.
struct SweepRules: Codable, Equatable {
    /// El remitente contiene alguno de estos textos (dirección o dominio).
    var senders: [String]
    var subjectRules: [SubjectRule]
    /// Nunca se barre un correo cuyo remitente contenga alguno de estos textos.
    var neverSweep: [String]
    /// Vaciar también la carpeta de correo no deseado de cada cuenta.
    var emptyJunk: Bool

    static let url: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barrendero", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("reglas.json")
    }()

    static func load() -> SweepRules {
        guard let data = try? Data(contentsOf: url), let rules = try? JSONDecoder().decode(SweepRules.self, from: data) else {
            return .defaults
        }
        return rules
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }

    /// Por qué se barre un correo, o nil si no se barre.
    func reason(sender: String, subject: String) -> String? {
        let from = sender.lowercased()
        if neverSweep.contains(where: { from.contains($0.lowercased()) }) { return nil }
        if let rule = subjectRules.first(where: { from.contains($0.sender.lowercased()) && subject.localizedCaseInsensitiveContains($0.subject) }) {
            return "\(rule.sender) · «\(rule.subject)»"
        }
        return senders.first { from.contains($0.lowercased()) }
    }

    /// Las reglas de la limpieza que hicimos en noviembre de 2026.
    static let defaults = SweepRules(
        senders: [
            // Viajes, aerolíneas y ofertas
            "aadvantage.email.aa.com", "info.email.aa.com", "alertadeprecio.v.avianca.com", "info.avianca.com",
            "news.avianca.com", "atrapalo", "boletines.iberia.com", "comunicaciones.iberia.com", "email.copa.com",
            "skyscanner.com", "tripadvisor.es", "invitation@airbnb.com", "lifemiles.com", "connectmiles.com",
            "ofertas@somosorlando.com", "todo.turismo@nacion.com",
            // Tiendas y bancos (promociones)
            "bcrsistematica@bancobcr.com", "beneficios@promerica.fi.cr", "promociones@beneficios.promerica.fi.cr",
            "ofertas.tiendamonge.com", "e.victoriassecret.com", "ct.vtex.com.br", "encuentra24.com", "unimart.com",
            "unimercentroamerica.com", "yuplon.com", "aliexpress.com", "temuemail.com", "order.alibaba.com",
            "no-responder@mercadolibre.com", "mispuntoscr.com", "cinexpress.cc", "marketingdhl.com", "concasa.com",
            "mkt-cr.didiglobal.com", "info.adt-worldwide.com", "freelotto.com", "sthonore.com.pa",
            // Boletines, cursos y noticias
            "boletines@emails.nacion.com", "emails.elfinancierocr.com", "estacion506cr.com", "editorialcostarica.com",
            "mailing.enfemenino.com", "newsletter@facilisimo.com", "nutricionate.com", "rawvana.com", "sweetpaleomx.com",
            "aprendeapintarconoleo.com", "my.simple.life", "studiovirtualarte.com", "soycomocomo.es", "metabolismotv.com",
            "newsletter.parade.com", "vg-esther.com", "vidente-esther", "ketolanders.com", "free-ebooks.net",
            "surveytaking.com", "felinacreativa.com", "thelbw.net", "lbwdaily.com", "queopinas.com", "justcloud.com",
            "fcbarcelona.com", "terraquea.com", "cloudcampuspro.com", "metaboosted.com", "cafecongatos.com",
            "dotmandalas4fun.com", "eastwesthealingacademy.com", "eduardovazquezia.com", "email.myiq.com",
            "laurodriguez.com", "memoriaagil.com", "mx2.4shared.com", "orbevida.com", "unimeal.com",
            "virtualianet.com", "websitebuilder.com", "whiterabbitinstituteofhealing.com", "wrihealing.com",
            // Redes y apps
            "facebookmail.com", "linkedin.com", "pinterest.com", "priority.instagram.com", "noreply@youtube.com",
            "email.nianticlabs.com", "email.skype.com", "communication.microsoft.com", "msn@e.microsoft.com",
            "insideapple.apple.com", "info.slide.com", "photos@onedrive.com", "mail.adobe.com", "email.adobe.com",
            "bevel_health", "e_zoom_us", "noreply@email.openai.com",
        ],
        subjectRules: [
            SubjectRule(sender: "bncr.fi.cr", subject: "Inicio de sesión"),
            SubjectRule(sender: "bncr.fi.cr", subject: "Comprobación Seguridad"),
        ],
        neverSweep: ["security", "seguridad@", "poder-judicial.go.cr", "hacienda.go.cr"],
        emptyJunk: true
    )
}

/// Ajustes de la limpieza automática.
enum Schedule {
    private static let defaults = UserDefaults.standard

    static var automatic: Bool {
        get { defaults.object(forKey: "automatic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "automatic") }
    }

    /// Mostrar la lista para confirmar antes de mover (si no, barre y avisa).
    static var askFirst: Bool {
        get { defaults.object(forKey: "askFirst") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "askFirst") }
    }

    /// Día de la semana (1 = domingo … 7 = sábado), a las 9:00.
    static var weekday: Int {
        get { defaults.object(forKey: "weekday") as? Int ?? 2 }
        set { defaults.set(newValue, forKey: "weekday") }
    }

    static var lastRun: Date? {
        get { defaults.object(forKey: "lastRun") as? Date }
        set { defaults.set(newValue, forKey: "lastRun") }
    }

    static var lastResult: String? {
        get { defaults.string(forKey: "lastResult") }
        set { defaults.set(newValue, forKey: "lastResult") }
    }

    /// Próxima limpieza: el día elegido a las 9:00, después de la última.
    static var nextRun: Date {
        let calendar = Calendar.current
        let after = lastRun ?? Date.distantPast
        let reference = max(after, calendar.date(byAdding: .day, value: -7, to: Date())!)
        return calendar.nextDate(after: reference, matching: DateComponents(hour: 9, minute: 0, weekday: weekday),
                                 matchingPolicy: .nextTime) ?? Date()
    }

    static let weekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
}
