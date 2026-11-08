import Foundation
import XCTest
@testable import AoE2MacTrainer

final class FeralMatchDetectorTests: XCTestCase {
    private var vfs: URL!
    private var saves: URL!
    private var recording: URL!
    private var info: URL!
    private let roster = """
    Single/Multiplayer: Singleplayer
    When game started: 23:59 2020/11/08
    GameOptions:
    {
      Civilisation Set: Age of Empires II
      Data Mod: Набор данных игры
      Number of Players: 2
      Player 1:
        Humanity: AI
        Civilization: Japanese
      Player 2:
        Name: Human: Player
        Humanity: Human
        Civilization: Portuguese
        Steam ID: 0
    }
    """

    override func setUpWithError() throws {
        vfs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        saves = vfs.appendingPathComponent("User/Games/Age of Empires 2 DE/12345/savegame")
        info = vfs.appendingPathComponent("Temp/CurrentGameInfo.txt")
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        recording = try record("SP Replay v101.103.57257.0 @2020.11.09 000001.aoe2record")
        try writeInfo(roster)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: vfs)
    }

    private func record(_ name: String) throws -> URL {
        let url = saves.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func detector(readOwner: @escaping (URL) -> String? = { _ in nil }) -> FeralMatchDetector {
        FeralMatchDetector(vfs: vfs, openFiles: { FeralMatchDetector.writableFiles(pid: getpid()) }, readOwner: readOwner)
    }

    private func writeInfo(_ text: String, time: String = "2020.11.08 235958") throws {
        try text.write(to: info, atomically: true, encoding: .utf8)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy.MM.dd HHmmss"
        try FileManager.default.setAttributes([.creationDate: try XCTUnwrap(formatter.date(from: time))],
                                              ofItemAtPath: info.path)
    }

    func testAttachesAcrossMidnightAndRemainsAttachedDuringPauseThenLeavesAndRejoins() throws {
        let detector = detector()
        let reader = try FileHandle(forReadingFrom: recording)
        defer { try? reader.close() }
        XCTAssertNil(detector.currentMatch())
        let writer = try FileHandle(forUpdating: recording)
        let first = try XCTUnwrap(detector.currentMatch())
        XCTAssertEqual(first.civilizationID, "portuguese")
        XCTAssertEqual(detector.currentMatch(), first)
        try writer.close()
        XCTAssertNil(detector.currentMatch())
        let writer2 = try FileHandle(forWritingTo: recording)
        defer { try? writer2.close() }
        XCTAssertEqual(detector.currentMatch(), first)
    }

    func testAdjacentStartsCanMakeMetadataAmbiguousAndOldMetadataExpires() throws {
        let writer = try FileHandle(forWritingTo: recording)
        defer { try? writer.close() }
        let detector = detector()
        _ = try record("SP Replay v101.103.57257.0 @2020.11.08 235952.aoe2record")
        XCTAssertNil(try XCTUnwrap(detector.currentMatch()).civilizationID)
        try writeInfo(roster, time: "2020.11.08 235940")
        XCTAssertNil(try XCTUnwrap(detector.currentMatch()).civilizationID)
    }

    func testStaleRecWrongDirectoryAndMultipleWritersCannotSelectAMatch() throws {
        let ignored = [try record("rec.aoe2record"), vfs.appendingPathComponent(recording.lastPathComponent)]
        try Data().write(to: ignored[1])
        let handles = try ignored.map(FileHandle.init(forWritingTo:))
        defer { handles.forEach { try? $0.close() } }
        let detector = detector()
        XCTAssertNil(detector.currentMatch())
        let writers = try [recording!, record("SP Replay v101.103.57257.0 @2020.11.09 000024.aoe2record")]
            .map(FileHandle.init(forWritingTo:))
        defer { writers.forEach { try? $0.close() } }
        XCTAssertNil(detector.currentMatch())
    }

    func testMissingOrIncompleteOrAmbiguousRosterNeverReturnsOpponent() throws {
        let writer = try FileHandle(forWritingTo: recording)
        defer { try? writer.close() }
        let detector = detector()
        for bad in [roster.replacingOccurrences(of: "Civilisation Set: Age of Empires II", with: "Civilisation Set: Return of Rome"),
                    roster.replacingOccurrences(of: "Набор данных игры", with: "Custom Dataset"),
                    roster.replacingOccurrences(of: "Humanity: AI", with: "Humanity: Human"),
                    roster.replacingOccurrences(of: "Number of Players: 2", with: "Number of Players: 3"),
                    roster.replacingOccurrences(of: "Portuguese", with: "Random"),
                    roster.replacingOccurrences(of: "23:59 2020/11/08", with: "22:59 2020/11/08"),
                    String(roster.dropLast())] {
            try writeInfo(bad)
            XCTAssertNil(try XCTUnwrap(detector.currentMatch()).civilizationID)
        }
        try FileManager.default.removeItem(at: info)
        XCTAssertNil(try XCTUnwrap(detector.currentMatch()).civilizationID)
    }

    func testRecordingOwnerWinsAndNewMatchInvalidatesCachedOwner() throws {
        var writer = try FileHandle(forWritingTo: recording)
        defer { try? writer.close() }
        var owner: String? = "turks"
        var reads = 0
        let detector = detector(readOwner: { _ in
            reads += 1
            return owner
        })
        let first = try XCTUnwrap(detector.currentMatch())
        XCTAssertEqual(first.civilizationID, "turks")
        XCTAssertEqual(detector.currentMatch(), first)
        XCTAssertEqual(reads, 1)
        try writer.close()
        let current = try record("MP Replay v101.103.57257.0 @2020.11.09 000020 (2).aoe2record")
        writer = try FileHandle(forWritingTo: current)
        owner = nil
        try writeInfo(roster.replacingOccurrences(of: "Singleplayer", with: "Multiplayer")
            .replacingOccurrences(of: "Humanity: AI", with: "Humanity: Human"))
        let next = try XCTUnwrap(detector.currentMatch())
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertNil(next.civilizationID)
        XCTAssertEqual(detector.currentMatch(), next)
        XCTAssertEqual(reads, 2)
        try Data([1]).write(to: current)
        owner = "spanish"
        XCTAssertEqual(detector.currentMatch()?.civilizationID, "spanish")
        XCTAssertEqual(reads, 3)
    }

    func testReplacementBetweenDescriptorSnapshotAndOpenSkipsDecoder() throws {
        let writer = try FileHandle(forWritingTo: recording)
        defer { try? writer.close() }
        let detector = FeralMatchDetector(vfs: vfs, openFiles: {
            let original = FeralMatchDetector.writableFiles(pid: getpid())
            do { try Data([2]).write(to: self.recording, options: .atomic) }
            catch { XCTFail("Replacement failed: \(error)") }
            return original
        }, readOwner: { _ in XCTFail("Attempted to decode replacement"); return "turks" })
        XCTAssertNil(detector.currentMatch())
    }

    func testReplacementDuringDecodeCannotRedirectReaderOrPublishCachedOwner() throws {
        try Data([1]).write(to: recording)
        let writer = try FileHandle(forWritingTo: recording)
        defer { try? writer.close() }
        let detector = detector { pinned in
            do {
                try Data([2]).write(to: self.recording, options: .atomic)
                XCTAssertEqual(try Data(contentsOf: pinned), Data([1]))
            } catch { XCTFail("Could not verify pinned file: \(error)") }
            return "turks"
        }
        XCTAssertNil(detector.currentMatch())
        XCTAssertNil(detector.currentMatch())
    }

    func testClosingWriterDuringDecodeDetachesEvenWhenFileStillExists() throws {
        let writer = try FileHandle(forWritingTo: recording)
        let detector = detector { _ in
            do { try writer.close() } catch { XCTFail("Could not close writer: \(error)") }
            return "turks"
        }
        XCTAssertNil(detector.currentMatch())
        XCTAssertNil(detector.currentMatch())
    }
}
