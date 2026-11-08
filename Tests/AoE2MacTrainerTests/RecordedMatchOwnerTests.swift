import Foundation
import XCTest
@testable import AoE2MacTrainer

final class RecordedMatchOwnerTests: XCTestCase {
    func testRecorderUsesResolvedCivilizationAndPlayerNumber() throws {
        XCTAssertEqual(try identify(recording(owner: 2)), "portuguese")
        XCTAssertEqual(try identify(recording(owner: 1)), "romans")
        XCTAssertEqual(try identify(recording(owner: 2, withAI: true)), "portuguese")
    }

    func testRejectsUnknownOrAmbiguousOwnersAndDatasets() throws {
        for bytes in [recording(owner: 0), recording(owner: 3), recording(owner: 2, duplicate: true),
                      recording(owner: 2, human: false), recording(owner: 2, dlc: 11),
                      recording(owner: 2, mod: "modified"), recording(owner: 2, build: 188330),
                      recording(owner: 2, ownerCiv: 48), recording(owner: 2, countWithGaia: 8)] {
            XCTAssertNil(try identify(bytes))
        }
    }

    func testPartialHeaderReturnsUnknown() throws {
        let bytes = recording(owner: 2)
        for size in [0, 4, 8, bytes.count / 2, bytes.count - 1] {
            XCTAssertNil(try identify(Data(bytes.prefix(size))))
        }
    }

    private func identify(_ data: Data) throws -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return RecordedMatchOwner.civilizationID(at: url)
    }

    // Synthetic DE header. Empty slot strings and hand-built settings contain no player data.
    private func recording(owner: UInt16, withAI: Bool = false, duplicate: Bool = false,
                           human: Bool = true, dlc: UInt32 = 2, mod: String = "",
                           build: UInt32 = 188329, ownerCiv: UInt32 = 24,
                           countWithGaia: UInt8 = 3) -> Data {
        var header = Data("VER 9.4\0".utf8)
        func u32(_ n: UInt32) { header.append(contentsOf: withUnsafeBytes(of: n.littleEndian, Array.init)) }
        func zeros(_ n: Int) { header.append(Data(repeating: 0, count: n)) }
        func string(_ s: String = "") {
            header.append(contentsOf: [0x60, 0x0a, UInt8(s.utf8.count), 0])
            header.append(contentsOf: s.utf8)
        }
        let speed = Float(1.69).bitPattern
        u32(0xbf800000)
        u32(0x0044e666)
        u32(build)
        zeros(16)
        u32(1)
        u32(dlc)
        zeros(48)
        u32(speed)
        zeros(8)
        u32(2)
        zeros(42)
        for slot in 0..<8 {
            zeros(20)
            u32(slot == 0 ? ownerCiv : 43)
            u32(0)
            string()
            zeros(1)
            string()
            string()
            string()
            u32(slot == 0 && !human ? 4 : 2)
            zeros(8)
            u32(slot == 0 ? 2 : slot == 1 ? (duplicate ? 2 : 1) : UInt32.max)
            zeros(14)
            string()
        }
        zeros(29)
        u32(1)
        zeros(8)
        for _ in 0..<20 { u32(1) }
        zeros(12 + 24)
        string()
        zeros(8)
        string(mod)
        zeros(92 + 4 + 12)
        string()
        zeros(24)
        u32(withAI ? 1 : 0)
        if withAI { header.append(0xff); zeros(4096) }
        zeros(24)
        u32(speed)
        zeros(17)
        header.append(contentsOf: withUnsafeBytes(of: owner.littleEndian, Array.init))
        header.append(countWithGaia)
        zeros(64)
        // One final uncompressed DEFLATE block (RFC 1951), inside the eight-byte envelope.
        let length = UInt16(header.count)
        let total = UInt32(header.count + 13)
        var file = Data(withUnsafeBytes(of: total.littleEndian, Array.init))
        file.append(contentsOf: [0, 0, 0, 0, 1])
        file.append(contentsOf: withUnsafeBytes(of: length.littleEndian, Array.init))
        file.append(contentsOf: withUnsafeBytes(of: (~length).littleEndian, Array.init))
        file.append(header)
        return file
    }
}
