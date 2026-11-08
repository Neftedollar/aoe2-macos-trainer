import Foundation
import XCTest
@testable import AoE2MacTrainer

final class CivilizationTests: XCTestCase {
    func testStandardIDsMatchTheEngineConstantsRatherThanUIPositions() {
        // Reference: https://ugc.aoe2.rocks/general/xs/constants/constants/
        // Explicit pairs catch an off-by-one shift or a wrong name/ID association.
        let expected: [String: Int] = [
            "britons": 1, "franks": 2, "goths": 3, "teutons": 4,
            "japanese": 5, "chinese": 6, "byzantines": 7, "persians": 8,
            "saracens": 9, "turks": 10, "vikings": 11, "mongols": 12,
            "celts": 13, "spanish": 14, "aztecs": 15, "mayans": 16,
            "huns": 17, "koreans": 18, "italians": 19, "hindustanis": 20,
            "incas": 21, "magyars": 22, "slavs": 23, "portuguese": 24,
            "ethiopians": 25, "malians": 26, "berbers": 27, "khmer": 28,
            "malay": 29, "burmese": 30, "vietnamese": 31, "bulgarians": 32,
            "tatars": 33, "cumans": 34, "lithuanians": 35, "burgundians": 36,
            "sicilians": 37, "poles": 38, "bohemians": 39, "dravidians": 40,
            "bengalis": 41, "gurjaras": 42, "romans": 43, "armenians": 44,
            "georgians": 45, "shu": 49, "wu": 50, "wei": 51,
            "jurchens": 52, "khitans": 53, "muisca": 57, "mapuche": 58,
            "tupi": 59, "saxons": 60, "varangians": 61, "danes": 62
        ]
        XCTAssertEqual(CivilizationCatalog.standard.count, expected.count)
        for civilization in CivilizationCatalog.standard {
            XCTAssertEqual(civilization.xsID, expected[civilization.id], civilization.id)
        }
    }

    func testStandardCatalogUsesUniquePositiveIDsAndCanonicalASCIIKeys() {
        let civilizations = CivilizationCatalog.standard
        XCTAssertEqual(Set(civilizations.map(\.id)).count, civilizations.count)
        XCTAssertEqual(Set(civilizations.map(\.xsID)).count, civilizations.count)
        XCTAssertTrue(civilizations.allSatisfy { $0.xsID > 0 && !$0.name.isEmpty })
        for civilization in civilizations {
            XCTAssertNotNil(civilization.id.range(of: "^[a-z]+(?:-[a-z]+)*$",
                                                 options: .regularExpression))
        }
        XCTAssertEqual(civilizations.map(\.xsID),
                       Array(1...45) + Array(49...53) + Array(57...62))
    }

    func testEveryCanonicalEnglishAndDisplayNameResolvesToTheSameIdentity() {
        for civilization in CivilizationCatalog.standard {
            XCTAssertEqual(CivilizationCatalog.resolve(civilization.id), civilization)
            XCTAssertEqual(CivilizationCatalog.resolve(civilization.id.capitalized), civilization)
            XCTAssertEqual(CivilizationCatalog.resolve(civilization.name), civilization)
            XCTAssertEqual(CivilizationCatalog.resolve(" \n\(civilization.name.uppercased())\t "),
                           civilization)
        }
    }

    func testExistingRussianBuildLabelsAndAliasesResolve() {
        let expected: [String: String] = [
            "Франки": "franks", "Мадьяры": "magyars", "Берберы": "berbers",
            "Гунны": "huns", "Бритты": "britons", "Эфиопы": "ethiopians",
            "Майя": "mayans", "Вьетнамцы": "vietnamese",
            "Португальцы": "portuguese", "Испанцы": "spanish",
            "Армяне": "armenians", "Грузины": "georgians", "Азтеки": "aztecs",
            "Бирманцы": "burmese", "Литовцы": "lithuanians", "Турки": "turks",
            "Итальянцы": "italians", "Тевтоны": "teutons", "Славяне": "slavs",
            "Индийцы": "hindustanis", "Indians": "hindustanis",
            "Британцы": "britons", "Венгры": "magyars", "Половцы": "cumans",
            "Бургундцы": "burgundians", "Чехи": "bohemians",
            "Вей": "wei", "Чжурчжени": "jurchens", "Муиска": "muisca"
        ]
        for (alias, id) in expected {
            XCTAssertEqual(CivilizationCatalog.resolve(alias)?.id, id, alias)
        }
    }

    func testUnknownWildcardsAndPartialNamesNeverSelectACivilization() {
        for raw in ["", " ", "\n\t", "Любая", "любые", "Все", "Any", "all", "*",
                    "random", "Gaia", "0", "24", "port", "Portuguese, Armenians",
                    "portuguese-extra", "unknown", "Achaemenids", "Athenians"] {
            XCTAssertNil(CivilizationCatalog.resolve(raw), raw)
        }
    }

    func testDefinitionCodableRoundTripPreservesStableIdentity() throws {
        let civilization = try XCTUnwrap(CivilizationCatalog.resolve("PORTUGUESE"))
        let data = try JSONEncoder().encode(civilization)
        XCTAssertEqual(try JSONDecoder().decode(CivilizationDefinition.self, from: data),
                       civilization)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "name", "xsID"])
        XCTAssertEqual(object["id"] as? String, "portuguese")
        XCTAssertEqual(object["xsID"] as? Int, 24)
    }
}
