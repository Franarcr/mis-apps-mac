import Foundation

enum MetalScene: String, CaseIterable, Identifiable, Codable {
    case noruega, sueciaFinlandia, deathEEUU, thrashEEUU, alemania, europa, latam, guitarra, tuyas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noruega: "Noruega"
        case .sueciaFinlandia: "Suecia y Finlandia"
        case .deathEEUU: "Death de Florida y EE. UU."
        case .thrashEEUU: "Thrash de EE. UU."
        case .alemania: "Thrash alemán"
        case .europa: "Resto de Europa y Canadá"
        case .latam: "Latinoamérica"
        case .guitarra: "Guitarras y técnica"
        case .tuyas: "Costa Rica y tus preguntas"
        }
    }

    var subtitle: String {
        switch self {
        case .noruega: "Black metal, Helvete, Grieghallen"
        case .sueciaFinlandia: "HM-2, Sunlight, Gotemburgo"
        case .deathEEUU: "Tampa, Morrisound, Nueva York"
        case .thrashEEUU: "Bay Area y Los Ángeles"
        case .alemania: "Essen, Gelsenkirchen, el sur"
        case .europa: "Inglaterra, Suiza, Grecia, Polonia"
        case .latam: "Belo Horizonte, Medellín, Santiago"
        case .guitarra: "Afinaciones, púa, pastillas"
        case .tuyas: "Las que tú agregas"
        }
    }

    var icon: String {
        switch self {
        case .noruega: "snowflake"
        case .sueciaFinlandia: "bolt.fill"
        case .deathEEUU: "drop.fill"
        case .thrashEEUU: "flame.fill"
        case .alemania: "hammer.fill"
        case .europa: "globe.europe.africa.fill"
        case .latam: "globe.americas.fill"
        case .guitarra: "guitars.fill"
        case .tuyas: "square.and.pencil"
        }
    }
}

struct Question: Identifiable, Codable, Hashable {
    var id = UUID()
    var scene: MetalScene
    var text: String
    /// La primera es la correcta; se barajan al mostrarlas.
    var options: [String]
    var fact: String
}

private func q(_ scene: MetalScene, _ text: String, _ right: String, _ w1: String, _ w2: String, _ w3: String, _ fact: String) -> Question {
    Question(scene: scene, text: text, options: [right, w1, w2, w3], fact: fact)
}

/// Solo datos bien documentados. Si alguno resulta dudoso, se corrige aquí.
let builtInQuestions: [Question] = [
    // MARK: Noruega
    q(.noruega, "¿En qué año salió «De Mysteriis Dom Sathanas» de Mayhem?", "1994", "1991", "1996", "1989",
      "Se grabó en Grieghallen (Bergen) y salió después de la muerte de Euronymous."),
    q(.noruega, "¿Cómo se llamaba la tienda de discos de Euronymous en Oslo, punto de encuentro de la escena?", "Helvete", "Grieghallen", "Deathlike Silence", "Nidrosian Black",
      "Helvete significa «infierno». Su sello era Deathlike Silence Productions."),
    q(.noruega, "Darkthrone empezó tocando death metal. ¿Cuál fue su primer disco?", "Soulside Journey", "A Blaze in the Northern Sky", "Transilvanian Hunger", "Panzerfaust",
      "Soulside Journey (1991) se grabó en Sunlight Studio, en Suecia. Luego viraron al black metal."),
    q(.noruega, "¿Qué disco de Darkthrone, de 1994, es famoso por sus riffs de trémolo hipnóticos?", "Transilvanian Hunger", "Under a Funeral Moon", "Panzerfaust", "Total Death",
      "Toda la música la compuso Fenriz."),
    q(.noruega, "Burzum era el proyecto de una sola persona. ¿De quién?", "Varg Vikernes", "Euronymous", "Fenriz", "Ihsahn",
      "Vikernes grabó también el bajo en «De Mysteriis Dom Sathanas» de Mayhem."),
    q(.noruega, "«In the Nightside Eclipse» (1994) es el primer disco de…", "Emperor", "Immortal", "Satyricon", "Enslaved",
      "Emperor venía de Telemark. Ihsahn y Samoth eran adolescentes cuando lo grabaron."),
    q(.noruega, "¿De qué ciudad noruega son Immortal y Gorgoroth?", "Bergen", "Oslo", "Trondheim", "Stavanger",
      "Bergen también es la ciudad del estudio Grieghallen y de Burzum."),
    q(.noruega, "¿Qué banda llevó el black metal a temas vikingos con «Vikingligr Veldi» (1994)?", "Enslaved", "Ulver", "Darkthrone", "Mayhem",
      "Enslaved es de Haugesund, en la costa oeste de Noruega."),
    q(.noruega, "¿Qué estudio de Bergen, con el productor Pytten, grabó a Burzum, Immortal y Emperor?", "Grieghallen", "Sunlight Studio", "Morrisound", "Studio Fredman",
      "Grieghallen es una sala de conciertos que también tiene estudio de grabación."),
    q(.noruega, "¿De qué país era Dead, vocalista de Mayhem?", "Suecia", "Noruega", "Finlandia", "Dinamarca",
      "Per Yngve Ohlin cantó antes en la banda sueca Morbid."),
    q(.noruega, "Abbath y Demonaz fundaron…", "Immortal", "Gorgoroth", "Satyricon", "Emperor",
      "Demonaz dejó la guitarra por una tendinitis, pero siguió escribiendo las letras."),
    q(.noruega, "«Nemesis Divina» (1996) es un disco de…", "Satyricon", "Dimmu Borgir", "Emperor", "Ulver",
      "Incluye «Mother North», uno de los videos más conocidos del black noruego."),
    q(.noruega, "¿En qué año salió el EP «Deathcrush» de Mayhem?", "1987", "1984", "1990", "1992",
      "Fue el primer lanzamiento de la banda, en edición muy limitada."),
    q(.noruega, "¿Cuál fue el primer disco de Ulver, que mezcla black metal y folk?", "Bergtatt", "Kveldssanger", "Nattens Madrigal", "Perdition City",
      "Bergtatt (1995) forma una trilogía con Kveldssanger y Nattens Madrigal."),
    q(.noruega, "¿En qué año salió «Filosofem» de Burzum?", "1996", "1993", "1999", "1991",
      "Se grabó antes, pero salió cuando Vikernes ya estaba en prisión."),

    // MARK: Suecia y Finlandia
    q(.sueciaFinlandia, "Bathory, pionero del black y del viking metal, era el proyecto de…", "Quorthon", "Dead", "Jon Nödtveidt", "Tomas Lindberg",
      "Quorthon (Tomas Forsberg) fundó Bathory en Estocolmo en 1983."),
    q(.sueciaFinlandia, "¿Qué disco de Bathory (1988) se considera el inicio del viking metal?", "Blood Fire Death", "Under the Sign of the Black Mark", "The Return……", "Twilight of the Gods",
      "La portada usa la pintura «La cacería salvaje de Odín», de Peter Nicolai Arbo."),
    q(.sueciaFinlandia, "El sonido «motosierra» del death sueco sale de un pedal. ¿Cuál?", "Boss HM-2", "Ibanez Tube Screamer", "ProCo RAT", "Boss DS-1",
      "Con todos los controles al máximo, el HM-2 da ese tono áspero de Entombed y Dismember."),
    q(.sueciaFinlandia, "¿En qué estudio de Estocolmo, con Tomas Skogsberg, se grabó el death sueco clásico?", "Sunlight Studio", "Grieghallen", "Morrisound", "Abyss Studio",
      "Ahí grabaron Entombed, Dismember, Grave y hasta Darkthrone en su etapa death."),
    q(.sueciaFinlandia, "Antes de llamarse Entombed, la banda se llamaba…", "Nihilist", "Carnage", "Grave", "Treblinka",
      "Treblinka fue el primer nombre de Tiamat, no de Entombed."),
    q(.sueciaFinlandia, "¿En qué año salió «Left Hand Path» de Entombed?", "1990", "1987", "1993", "1995",
      "Es uno de los discos que definió el death metal de Estocolmo."),
    q(.sueciaFinlandia, "«Like an Ever Flowing Stream» (1991) es el primer disco de…", "Dismember", "Entombed", "Unleashed", "Grave",
      "También se grabó en Sunlight con el pedal HM-2."),
    q(.sueciaFinlandia, "¿De qué ciudad salió el death melódico de At the Gates, In Flames y Dark Tranquillity?", "Gotemburgo", "Estocolmo", "Malmö", "Uppsala",
      "Muchos grabaron en Studio Fredman, con Fredrik Nordström."),
    q(.sueciaFinlandia, "¿En qué año salió «Slaughter of the Soul» de At the Gates?", "1995", "1991", "1999", "1993",
      "Después de ese disco la banda se separó por más de diez años."),
    q(.sueciaFinlandia, "¿Quién lideraba Dissection, autores de «Storm of the Light's Bane»?", "Jon Nödtveidt", "Quorthon", "Tomas Lindberg", "Lars-Göran Petrov",
      "Lars-Göran Petrov fue la voz de Entombed; Tomas Lindberg, la de At the Gates."),
    q(.sueciaFinlandia, "¿De qué país es Marduk, autores de «Panzer Division Marduk» (1999)?", "Suecia", "Noruega", "Finlandia", "Alemania",
      "Marduk es de Norrköping."),
    q(.sueciaFinlandia, "«Nespithe» (1993), un death metal rarísimo y técnico, es el único disco de…", "Demilich", "Amorphis", "Convulse", "Sentenced",
      "Demilich es finlandés, famoso por su voz gutural extremadamente grave."),
    q(.sueciaFinlandia, "¿De qué país es Beherit, autores de «Drawing Down the Moon» (1993)?", "Finlandia", "Suecia", "Noruega", "Grecia",
      "Beherit es clave en el black metal crudo finlandés."),
    q(.sueciaFinlandia, "«Tales from the Thousand Lakes» (1994) de Amorphis se inspira en…", "El Kalevala", "La Edda", "Lovecraft", "La Divina Comedia",
      "El Kalevala es la epopeya nacional de Finlandia."),
    q(.sueciaFinlandia, "¿De qué país es Impaled Nazarene?", "Finlandia", "Suecia", "Polonia", "Noruega",
      "Su primer disco es «Tol Cormpt Norz Norz Norz» (1993)."),

    // MARK: Death de Florida y EE. UU.
    q(.deathEEUU, "Chuck Schuldiner fundó y lideró…", "Death", "Obituary", "Morbid Angel", "Atheist",
      "Chuck murió en 2001; se le llama «el padre del death metal»."),
    q(.deathEEUU, "¿En qué año salió «Scream Bloody Gore», primer disco de Death?", "1987", "1985", "1989", "1991",
      "Chris Reifert tocó la batería en ese disco."),
    q(.deathEEUU, "«Human» (1991) de Death tuvo a dos músicos de Cynic. ¿Quiénes?", "Paul Masvidal y Sean Reinert", "Trey Azagthoth y Pete Sandoval", "John y Donald Tardy", "Kelly Shaefer y Steve Flynn",
      "Steve DiGiorgio tocó el bajo en ese mismo disco."),
    q(.deathEEUU, "¿Qué estudio de Tampa, con Scott Burns, grabó a casi todo el death de Florida?", "Morrisound", "Sunlight Studio", "Grieghallen", "Studio Fredman",
      "Ahí pasaron Death, Obituary, Deicide, Cannibal Corpse y Morbid Angel."),
    q(.deathEEUU, "Los discos de Morbid Angel van en orden alfabético. ¿Cuál fue el primero?", "Altars of Madness", "Blessed Are the Sick", "Covenant", "Domination",
      "Altars of Madness salió en 1989."),
    q(.deathEEUU, "¿Quién fundó Morbid Angel y es su guitarrista desde el principio?", "Trey Azagthoth", "Chuck Schuldiner", "Jack Owen", "Trevor Peres",
      "Jack Owen tocó en Cannibal Corpse y Trevor Peres en Obituary."),
    q(.deathEEUU, "«Slowly We Rot» (1989) es el primer disco de…", "Obituary", "Deicide", "Massacre", "Monstrosity",
      "La voz de John Tardy es una de las más reconocibles del género."),
    q(.deathEEUU, "Glen Benton es voz y bajo de…", "Deicide", "Cannibal Corpse", "Obituary", "Malevolent Creation",
      "Deicide sacó su primer disco en 1990."),
    q(.deathEEUU, "¿En qué ciudad se formó Cannibal Corpse?", "Buffalo, Nueva York", "Tampa", "Los Ángeles", "Chicago",
      "Se formaron en 1988 y luego se mudaron a Tampa."),
    q(.deathEEUU, "«Seven Churches» (1985), de los primeros discos de death metal, es de…", "Possessed", "Death", "Slayer", "Kreator",
      "Possessed es del Área de la Bahía; cierra el disco una canción llamada «Death Metal»."),
    q(.deathEEUU, "Suffocation, pionera del death brutal, es de…", "Nueva York", "Florida", "Texas", "California",
      "Su primer disco largo es «Effigy of the Forgotten» (1991)."),
    q(.deathEEUU, "Autopsy lo fundó Chris Reifert, quien antes tocó batería en…", "Death", "Obituary", "Possessed", "Exodus",
      "Autopsy es de Oakland, California; su primer disco es «Severed Survival» (1989)."),
    q(.deathEEUU, "¿Qué disco mezcló death metal con jazz fusión en 1993?", "Focus, de Cynic", "Human, de Death", "Altars of Madness, de Morbid Angel", "Effigy of the Forgotten, de Suffocation",
      "Cynic usaba guitarras sintetizadas y voces con vocoder."),

    // MARK: Thrash de EE. UU.
    q(.thrashEEUU, "«Bonded by Blood» (1985) es el primer disco de…", "Exodus", "Testament", "Forbidden", "Vio-lence",
      "Se grabó en 1984, pero salió un año después."),
    q(.thrashEEUU, "Antes de entrar a Metallica, Kirk Hammett fundó…", "Exodus", "Testament", "Death Angel", "Possessed",
      "Gary Holt tomó luego el liderazgo de Exodus."),
    q(.thrashEEUU, "«The Legacy» (1987) es el primer disco de…", "Testament", "Exodus", "Overkill", "Heathen",
      "Antes la banda se llamaba Legacy."),
    q(.thrashEEUU, "«The Ultra-Violence» (1987) es el primer disco de…", "Death Angel", "Dark Angel", "Vio-lence", "Forbidden",
      "Los miembros de Death Angel eran adolescentes cuando lo grabaron."),
    q(.thrashEEUU, "¿En qué año salió «Reign in Blood» de Slayer?", "1986", "1983", "1988", "1990",
      "Lo produjo Rick Rubin y dura menos de 30 minutos."),
    q(.thrashEEUU, "¿De dónde es Slayer?", "Los Ángeles (Huntington Park)", "San Francisco", "Nueva York", "Tampa",
      "Slayer no es del Área de la Bahía, sino del sur de California."),
    q(.thrashEEUU, "«Darkness Descends» (1986), con Gene Hoglan en la batería, es de…", "Dark Angel", "Testament", "Exodus", "Sacred Reich",
      "Gene Hoglan tocó después con Death en «Individual Thought Patterns»."),
    q(.thrashEEUU, "La cuna del thrash de Exodus, Testament y Death Angel es…", "El Área de la Bahía de San Francisco", "Nueva York", "Seattle", "Texas",
      "Por eso se habla del «Bay Area thrash»."),

    // MARK: Thrash alemán
    q(.alemania, "¿De qué ciudad alemana es Kreator?", "Essen", "Gelsenkirchen", "Berlín", "Hamburgo",
      "Mille Petrozza es su guitarrista y voz desde el inicio."),
    q(.alemania, "¿En qué año salió «Pleasure to Kill» de Kreator?", "1986", "1983", "1989", "1991",
      "Es uno de los discos de thrash más extremos de su época y una influencia en el death metal."),
    q(.alemania, "Tom Angelripper es voz y bajo de…", "Sodom", "Kreator", "Destruction", "Tankard",
      "Sodom es de Gelsenkirchen, en la cuenca minera del Ruhr."),
    q(.alemania, "«Agent Orange» (1989) es un disco de…", "Sodom", "Kreator", "Destruction", "Tankard",
      "Sodom tiene muchas letras sobre la guerra."),
    q(.alemania, "Schmier es voz y bajo de…", "Destruction", "Sodom", "Kreator", "Holy Moses",
      "Destruction es del sur de Alemania, cerca de la frontera con Suiza."),
    q(.alemania, "«Infernal Overkill» (1985) es el primer disco largo de…", "Destruction", "Sodom", "Kreator", "Living Death",
      "Antes habían sacado el EP «Sentence of Death» (1984)."),

    // MARK: Resto de Europa y Canadá
    q(.europa, "El disco «Black Metal» (1982), que dio nombre al género, es de…", "Venom", "Bathory", "Hellhammer", "Mercyful Fate",
      "Venom es de Newcastle, Inglaterra."),
    q(.europa, "¿De qué país eran Hellhammer y Celtic Frost?", "Suiza", "Alemania", "Austria", "Bélgica",
      "Tom G. Warrior lideró ambas bandas."),
    q(.europa, "«Morbid Tales» (1984) es el primer lanzamiento de…", "Celtic Frost", "Venom", "Bathory", "Sodom",
      "Celtic Frost nació de las cenizas de Hellhammer."),
    q(.europa, "«You Suffer», de Napalm Death, es famosa por…", "Durar alrededor de un segundo", "Durar más de 20 minutos", "Ser instrumental", "Grabarse en vivo",
      "Está en «Scum» (1987), disco clave del grindcore. Napalm Death es de Birmingham."),
    q(.europa, "Las primeras letras de Carcass usaban mucho…", "Términos médicos y forenses", "Mitología nórdica", "Ciencia ficción", "Política",
      "Carcass es de Liverpool; luego pasó al death melódico con «Heartwork» (1993)."),
    q(.europa, "«Realm of Chaos» (1989) de Bolt Thrower se inspira en…", "Warhammer 40.000", "El Señor de los Anillos", "La Segunda Guerra Mundial", "Lovecraft",
      "Bolt Thrower es de Coventry, Inglaterra."),
    q(.europa, "¿De qué país es Rotting Christ?", "Grecia", "Italia", "Portugal", "Turquía",
      "La lideran los hermanos Sakis y Themis Tolis, de Atenas."),
    q(.europa, "¿De qué país son Vader y Behemoth?", "Polonia", "República Checa", "Rusia", "Hungría",
      "«The Ultimate Incantation» (1992) de Vader fue de los primeros discos de death polaco en un sello internacional (Earache)."),
    q(.europa, "¿De qué país es Pestilence, autores de «Consuming Impulse» (1989)?", "Países Bajos", "Bélgica", "Alemania", "Dinamarca",
      "Asphyx, otro grande del death neerlandés, también viene de ahí."),
    q(.europa, "Voivod, el thrash más raro y progresivo de los 80, es de…", "Canadá (Quebec)", "Francia", "Bélgica", "Estados Unidos",
      "Su baterista Away dibuja las portadas de la banda."),
    q(.europa, "«Fallen Angel of Doom» (1990), base del «war metal», es de…", "Blasphemy, de Canadá", "Beherit, de Finlandia", "Sarcófago, de Brasil", "Archgoat, de Finlandia",
      "Blasphemy es de la zona de Vancouver."),

    // MARK: Latinoamérica
    q(.latam, "¿De qué ciudad brasileña es Sepultura?", "Belo Horizonte", "São Paulo", "Río de Janeiro", "Porto Alegre",
      "Belo Horizonte también es la cuna de Sarcófago y del sello Cogumelo."),
    q(.latam, "¿Qué hermanos fundaron Sepultura?", "Max e Igor Cavalera", "Andreas y Paulo Kisser", "Wagner y Gerald Lamounier", "Sakis y Themis Tolis",
      "Wagner Lamounier fue la voz de Sarcófago y estuvo en los primeros días de Sepultura."),
    q(.latam, "¿En qué año salió «Beneath the Remains» de Sepultura?", "1989", "1986", "1992", "1995",
      "Lo produjo Scott Burns y fue su primer disco con Roadrunner."),
    q(.latam, "«Roots», que mezcló metal con percusión indígena brasileña, salió en…", "1996", "1991", "1993", "1999",
      "Fue el último disco de Max Cavalera con Sepultura."),
    q(.latam, "«I.N.R.I.» (1987), una gran influencia para el black metal, es de…", "Sarcófago", "Sepultura", "Vulcano", "Holocausto",
      "Su imagen con cuero y clavos fue copiada luego por muchas bandas noruegas."),
    q(.latam, "¿Qué sello de Belo Horizonte sacó los primeros discos de Sepultura y Sarcófago?", "Cogumelo", "Roadrunner", "Earache", "Nuclear Blast",
      "Cogumelo empezó como una tienda de discos."),
    q(.latam, "¿De qué país son Masacre y Parabellum?", "Colombia", "Venezuela", "Ecuador", "Perú",
      "Ambas son de Medellín, una escena muy fuerte desde los años 80."),
    q(.latam, "Pentagram, la banda de thrash y death de Anton Reisenegger, es de…", "Chile", "Argentina", "Uruguay", "Bolivia",
      "No confundir con Pentagram de Estados Unidos, que es de doom."),
    q(.latam, "¿De qué país es Transmetal?", "México", "Colombia", "Brasil", "Chile",
      "Transmetal es una de las bandas más veteranas del thrash y death mexicano."),
    q(.latam, "¿De qué país es Mortem?", "Perú", "Bolivia", "Ecuador", "Chile",
      "Mortem es de Lima y lleva desde finales de los 80 en el death metal."),

    // MARK: Guitarras y técnica
    q(.guitarra, "Tocar la misma nota muy rápido con la púa, típico del black metal, se llama…", "Trémolo (tremolo picking)", "Palm mute", "Sweep picking", "Legato",
      "Con acordes abiertos y trémolo se logra la «pared» de sonido del black noruego."),
    q(.guitarra, "Bajar todas las cuerdas medio tono, como tu Dean, se llama…", "Afinación en Mi bemol (Eb)", "Drop D", "Drop C", "Afinación en Re (D estándar)",
      "Muchas bandas de thrash y death de los 80 tocaban medio tono abajo."),
    q(.guitarra, "Drop D significa…", "Bajar solo la 6ª cuerda a Re", "Bajar todas las cuerdas un tono", "Subir la 1ª cuerda a Re", "Bajar todas medio tono",
      "Así los power chords en las cuerdas graves se tocan con un solo dedo."),
    q(.guitarra, "¿En qué año presentó Gibson la forma Explorer, como tu Dean?", "1958", "1952", "1965", "1971",
      "Al principio casi no se vendió; luego el metal la hizo icónica."),
    q(.guitarra, "Dimebag Darrell, de Pantera, es famoso por usar una…", "Dean ML", "Gibson Explorer", "Jackson Randy Rhoads", "ESP Viper",
      "La Dean ML mezcla la forma Explorer con la Flying V."),
    q(.guitarra, "Apoyar el canto de la mano en las cuerdas junto al puente se llama…", "Palm mute", "Trémolo", "Tapping", "Bending",
      "Es la base del sonido «chug» del thrash."),
    q(.guitarra, "¿Por qué un humbucker hace menos ruido que una pastilla simple?", "Tiene dos bobinas que cancelan el zumbido", "Tiene imanes más débiles", "Va más lejos de las cuerdas", "Usa pilas",
      "Por eso suena más grueso y aguanta más distorsión: ideal para metal."),
    q(.guitarra, "El ritmo «D-beat» toma su nombre de la banda…", "Discharge", "Darkthrone", "Death", "Destruction",
      "Discharge es un grupo punk inglés de finales de los 70 que influyó al crust y al metal extremo."),
    q(.guitarra, "Un blast beat es…", "Bombo, caja y platillo muy rápidos y seguidos", "Un solo de batería lento", "Un ritmo de doble bombo a medio tiempo", "Una pausa antes del coro",
      "Napalm Death y luego el black y el death lo hicieron la marca del metal extremo."),
]
