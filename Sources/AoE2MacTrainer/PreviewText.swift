enum PreviewText {
    static func animals(_ count: Int) -> String {
        guard count > 0 else { return "Неизвестно" }
        return quantity(count, one: "животное", few: "животных", many: "животных")
    }

    static func builds(_ count: Int) -> String {
        quantity(count, one: "билд", few: "билда", many: "билдов")
    }

    static func villagers(_ count: Int) -> String {
        quantity(count, one: "крестьянин", few: "крестьянина", many: "крестьян")
    }

    private static func quantity(_ count: Int, one: String, few: String, many: String) -> String {
        let noun: String
        switch (count % 100, count % 10) {
        case (11...14, _): noun = many
        case (_, 1):       noun = one
        case (_, 2...4):   noun = few
        default:           noun = many
        }
        return "\(count) \(noun)"
    }
}

extension StartingFoodKind {
    var displayName: String {
        switch self {
        case .pushableHunt: return "Дичь для подгона к ТЦ"
        case .smallGame:    return "Мелкая дичь"
        }
    }
}
