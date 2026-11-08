import Foundation

/// Stable identity used in build JSON and the civilization ID returned by XS.
/// Display names never determine engine identity or build eligibility.
struct CivilizationDefinition: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let xsID: Int
}

enum CivilizationCatalog {
    /// Normal AoE2 civilizations, in engine-ID order, verified on 2026-11-08.
    /// Source: the Constants.xs reference, section "Aoe2 Civs":
    /// https://ugc.aoe2.rocks/general/xs/constants/constants/
    /// The engine getter is documented by Forgotten Empires:
    /// https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/xs-scripting-in-age-of-empires-ii-definitive-edition
    ///
    /// These are XS civilization IDs, NOT positions in a filtered UI list.
    /// IDs 46...48 and 54...56 belong to Chronicles and are deliberately omitted;
    /// Return of Rome has a separate ID space and is not included here either.
    /// Gaia (0), random civilization, and wildcard build selectors are not civs.
    static let standard: [CivilizationDefinition] = [
        .init(id: "britons", name: "Бритты", xsID: 1),
        .init(id: "franks", name: "Франки", xsID: 2),
        .init(id: "goths", name: "Готы", xsID: 3),
        .init(id: "teutons", name: "Тевтоны", xsID: 4),
        .init(id: "japanese", name: "Японцы", xsID: 5),
        .init(id: "chinese", name: "Китайцы", xsID: 6),
        .init(id: "byzantines", name: "Византийцы", xsID: 7),
        .init(id: "persians", name: "Персы", xsID: 8),
        .init(id: "saracens", name: "Сарацины", xsID: 9),
        .init(id: "turks", name: "Турки", xsID: 10),
        .init(id: "vikings", name: "Викинги", xsID: 11),
        .init(id: "mongols", name: "Монголы", xsID: 12),
        .init(id: "celts", name: "Кельты", xsID: 13),
        .init(id: "spanish", name: "Испанцы", xsID: 14),
        .init(id: "aztecs", name: "Ацтеки", xsID: 15),
        .init(id: "mayans", name: "Майя", xsID: 16),
        .init(id: "huns", name: "Гунны", xsID: 17),
        .init(id: "koreans", name: "Корейцы", xsID: 18),
        .init(id: "italians", name: "Итальянцы", xsID: 19),
        // Constants.xs retains the historical cIndians name for this ID.
        .init(id: "hindustanis", name: "Индостанцы", xsID: 20),
        .init(id: "incas", name: "Инки", xsID: 21),
        .init(id: "magyars", name: "Мадьяры", xsID: 22),
        .init(id: "slavs", name: "Славяне", xsID: 23),
        .init(id: "portuguese", name: "Португальцы", xsID: 24),
        .init(id: "ethiopians", name: "Эфиопы", xsID: 25),
        .init(id: "malians", name: "Малийцы", xsID: 26),
        .init(id: "berbers", name: "Берберы", xsID: 27),
        .init(id: "khmer", name: "Кхмеры", xsID: 28),
        .init(id: "malay", name: "Малайцы", xsID: 29),
        .init(id: "burmese", name: "Бирманцы", xsID: 30),
        .init(id: "vietnamese", name: "Вьетнамцы", xsID: 31),
        .init(id: "bulgarians", name: "Болгары", xsID: 32),
        .init(id: "tatars", name: "Татары", xsID: 33),
        .init(id: "cumans", name: "Куманы", xsID: 34),
        .init(id: "lithuanians", name: "Литовцы", xsID: 35),
        .init(id: "burgundians", name: "Бургунды", xsID: 36),
        .init(id: "sicilians", name: "Сицилийцы", xsID: 37),
        .init(id: "poles", name: "Поляки", xsID: 38),
        .init(id: "bohemians", name: "Богемцы", xsID: 39),
        .init(id: "dravidians", name: "Дравиды", xsID: 40),
        .init(id: "bengalis", name: "Бенгальцы", xsID: 41),
        .init(id: "gurjaras", name: "Гурджары", xsID: 42),
        .init(id: "romans", name: "Римляне", xsID: 43),
        .init(id: "armenians", name: "Армяне", xsID: 44),
        .init(id: "georgians", name: "Грузины", xsID: 45),
        .init(id: "shu", name: "Шу", xsID: 49),
        .init(id: "wu", name: "У", xsID: 50),
        .init(id: "wei", name: "Вэй", xsID: 51),
        .init(id: "jurchens", name: "Чжурчжэни", xsID: 52),
        .init(id: "khitans", name: "Кидани", xsID: 53),
        .init(id: "muisca", name: "Муиски", xsID: 57),
        .init(id: "mapuche", name: "Мапуче", xsID: 58),
        .init(id: "tupi", name: "Тупи", xsID: 59),
        .init(id: "saxons", name: "Саксы", xsID: 60),
        .init(id: "varangians", name: "Варяги", xsID: 61),
        .init(id: "danes", name: "Датчане", xsID: 62)
    ]

    /// Resolves a canonical slug, an English name, or a supported Russian label.
    /// This is an exact lookup after trimming/case normalization, never a fuzzy
    /// match. Unknown strings and wildcard selectors intentionally return nil.
    static func resolve(_ raw: String) -> CivilizationDefinition? {
        byAlias[normalized(raw)]
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Alternative labels accepted from older hand-authored build JSON. Each
    /// canonical slug already equals its current English name ignoring case.
    private static let legacyAliases: [String: [String]] = [
        "britons": ["Британцы"],
        "aztecs": ["Азтеки"],
        "hindustanis": ["Indians", "Индийцы", "Гиндустанцы"],
        "magyars": ["Венгры"],
        "cumans": ["Половцы"],
        "burgundians": ["Бургундцы"],
        "bohemians": ["Чехи"],
        "wei": ["Вей"],
        "jurchens": ["Чжурчжени"],
        "muisca": ["Муиска"]
    ]

    private static let byAlias: [String: CivilizationDefinition] = {
        var result: [String: CivilizationDefinition] = [:]
        for civilization in standard {
            let aliases = [civilization.id, civilization.name]
                + (legacyAliases[civilization.id] ?? [])
            for alias in aliases {
                let key = normalized(alias)
                precondition(result[key] == nil || result[key] == civilization,
                             "Ambiguous civilization alias: \(alias)")
                result[key] = civilization
            }
        }
        return result
    }()
}
