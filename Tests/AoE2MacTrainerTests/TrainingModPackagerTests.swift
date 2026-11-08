import Foundation
import XCTest
@testable import AoE2MacTrainer

final class TrainingModPackagerTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AoE2MacTrainer-Tests-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testPackagedModContainsRMSAndXS() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let build = try XCTUnwrap(BuildOrderLibrary.bundled().first { $0.map == "Арена" })
        let source = try XCTUnwrap(TrainingModPackager.builtinMap(for: build))
        let mod = try TrainingModPackager.install(build: build, source: source, into: temp)

        let xsName = XSBuildExporter.recommendedFileName(for: build)
        let xs = mod.appendingPathComponent("resources/_common/xs/\(xsName)")
        let rms = mod.appendingPathComponent("resources/_common/random-map-scripts/\(mod.lastPathComponent).rms")
        XCTAssertTrue(FileManager.default.fileExists(atPath: xs.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rms.path))
        let map = try String(contentsOf: rms, encoding: .utf8)
        XCTAssertTrue(map.contains("#includeXS \(xsName)"))
        XCTAssertTrue(map.contains("#include_drs Arena.rms"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mod.appendingPathComponent("info.json").path))
    }

    func testReinstallKeepsEarlierModIntact() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let build = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let source = try XCTUnwrap(TrainingModPackager.builtinMap(for: build))
        let first = try TrainingModPackager.install(build: build, source: source, into: temp)
        let second = try TrainingModPackager.install(build: build, source: source, into: temp)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.appendingPathComponent("info.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("info.json").path))
    }

    func testExistingRMSIsCopiedAndNotModified() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = temp.appendingPathComponent("personal_map.rms")
        let original = "<PLAYER_SETUP>\nrandom_placement\n"
        try original.write(to: source, atomically: true, encoding: .utf8)
        let build = try XCTUnwrap(BuildOrderLibrary.bundled().first)
        let mod = try TrainingModPackager.install(
            build: build, source: .selectedRMS(source),
            into: temp.appendingPathComponent("mods/local")
        )
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original)
        let map = try String(contentsOf:
            mod.appendingPathComponent("resources/_common/random-map-scripts/\(mod.lastPathComponent).rms"),
            encoding: .utf8
        )
        XCTAssertTrue(map.contains("#includeXS aoe2trainer_"))
        XCTAssertTrue(map.hasSuffix(original))
    }

    func testUnsafeMapPathsAndDuplicateXSIncludesAreRejected() throws {
        XCTAssertThrowsError(try TrainingModPackager.makeMapContents(
            source: .includedGameMap("../Arena.rms"), xsFilename: "trainer.xs"
        ))
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("other.rms")
        try "#includeXS already.xs\n<PLAYER_SETUP>\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try TrainingModPackager.makeMapContents(
            source: .selectedRMS(file), xsFilename: "trainer.xs"
        ))
    }

    func testFeralModDirectoryDiscoveryUsesActualProfiles() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let profile = temp.appendingPathComponent(
            "Library/Application Support/Feral Interactive/Age Of Empires II/VFS/User/Games/Age of Empires 2 DE/12345",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let folders = TrainingModPackager.detectedLocalModFolders(home: temp)
        XCTAssertEqual(folders, [profile.appendingPathComponent("mods/local", isDirectory: true)])
    }
}
