import AppKit
import Darwin
import Foundation

struct FeralMatch: Equatable {
    let id: String
    let civilizationID: String?
}

/// A writable match recording stays open during pause. Only its open descriptor signals a match.
/// CurrentGameInfo survives that transition and therefore cannot establish liveness.
final class FeralMatchDetector {
    private let vfs: URL
    struct RecordingWriter: Equatable {
        let url: URL
        let device: dev_t
        let inode: ino_t
        let pid: pid_t
        let fd: Int32

        var id: String { "\(url.path)#\(device):\(inode)" }
        func matches(_ info: stat) -> Bool { device == info.st_dev && inode == info.st_ino }
    }

    private let openFiles: () -> [RecordingWriter]
    private let readOwner: (URL) -> String?
    private var lastOwnerRead: (matchID: String, size: off_t, modification: Date, civilization: String?)?

    init(vfs: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Feral Interactive/Age Of Empires II/VFS"),
         openFiles: @escaping () -> [RecordingWriter] = FeralMatchDetector.gameWritableFiles,
         readOwner: @escaping (URL) -> String? = RecordedMatchOwner.civilizationID(at:)) {
        self.vfs = vfs
        self.openFiles = openFiles
        self.readOwner = readOwner
    }

    func currentMatch() -> FeralMatch? {
        let root = vfs.appendingPathComponent("User/Games/Age of Empires 2 DE").standardizedFileURL
        let recordings = openFiles().compactMap { writer -> (RecordingWriter, String, Date)? in
            let url = writer.url
            let saves = url.deletingLastPathComponent()
            let profile = saves.deletingLastPathComponent()
            guard saves.lastPathComponent == "savegame", UInt64(profile.lastPathComponent) != nil,
                  profile.deletingLastPathComponent().path == root.path,
                  let details = Self.recordingDetails(url.lastPathComponent) else { return nil }
            return (writer, details.mode, details.start)
        }
        guard let (writer, mode, start) = recordings.first, recordings.allSatisfy({ $0.0.id == writer.id }) else {
            lastOwnerRead = nil
            return nil
        }
        let recording = writer.url
        guard let reader = try? FileHandle(forReadingFrom: recording) else { return nil }
        defer { try? reader.close() }
        var info = stat()
        guard fstat(reader.fileDescriptor, &info) == 0, writer.matches(info) else { return nil }
        let id = writer.id
        let modification = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
        let owner: String?
        if let cached = lastOwnerRead, cached.matchID == id,
           cached.civilization != nil || (cached.size == info.st_size && cached.modification == modification) {
            owner = cached.civilization
        } else {
            // /dev/fd duplicates this verified handle. A rename cannot redirect the decoder.
            owner = readOwner(URL(fileURLWithPath: "/dev/fd/\(reader.fileDescriptor)"))
        }
        let civilization = owner ?? ownCivilization(recording: recording, mode: mode, start: start)
        // Recheck this single FD after decoding rather than listing all game files again.
        // Closing it, reusing its number or replacing the directory entry invalidates the poll.
        var current = stat()
        guard stat(recording.path, &current) == 0, writer.matches(current),
              Self.recordingWriter(pid: writer.pid, fd: writer.fd) == writer else {
            lastOwnerRead = nil
            return nil
        }
        lastOwnerRead = (id, info.st_size, modification, owner)
        return FeralMatch(id: id, civilizationID: civilization)
    }

    private static let filename = try! NSRegularExpression(
        pattern: #"^(SP|MP) Replay v[0-9.]+ @(\d{4}\.\d{2}\.\d{2} \d{6})(?: \([0-9]+\))?\.aoe2record$"#)

    private static func recordingDetails(_ name: String) -> (mode: String, start: Date)? {
        let string = name as NSString
        guard let match = filename.firstMatch(in: name, range: NSRange(location: 0, length: string.length)),
              let start = date(string.substring(with: match.range(at: 2)), format: "yyyy.MM.dd HHmmss") else {
            return nil
        }
        return (string.substring(with: match.range(at: 1)) == "SP" ? "Singleplayer" : "Multiplayer", start)
    }

    private static func date(_ raw: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter.date(from: raw)
    }

    // Localized labels for IDS_GAME_DATA_SET_DESCRIPTION_FORGOTTEN in the shipped game.
    private static let standardDataMods: Set<String> = [
        "Bộ dữ liệu trò chơi nguyên bản",
        "Enviar Conjunto de datos del juego",
        "Enviar Dataset del juego",
        "Envoi des données",
        "Invio dataset gioco",
        "Liberando Dados do Jogo",
        "Menggunakan Set Data",
        "Oyun Veri Seti Gönderiliyor",
        "Pierwotny zestaw danych gry.",
        "Shipping Game Dataset",
        "Spieldatensatz wird veröffentlicht",
        "Набор данных игры",
        "खेल डेटासेट शिप करना",
        "ゲーム データセットを移出中",
        "正在发行游戏数据集",
        "正在發行遊戲資料集",
        "게임 데이터 세트를 꾸리는 중",
    ]

    private func ownCivilization(recording: URL, mode: String, start: Date) -> String? {
        guard mode == "Singleplayer" else { return nil }
        let url = vfs.appendingPathComponent("Temp/CurrentGameInfo.txt")
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0, info.st_size > 0, info.st_size <= 131072,
              let data = try? file.read(upToCount: Int(info.st_size)), data.count == Int(info.st_size),
              let content = String(data: data, encoding: .utf8) else { return nil }
        let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec))
        // Feral writes this file shortly before starting the recorder (3 seconds observed).
        // Its contents and mtime can update during the match. The inode birth time
        // stays at the start, regardless of subsequent writes or pauses.
        let tolerance = 10.0
        guard abs(created.timeIntervalSince(start)) <= tolerance else { return nil }
        let lines = content.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard lines.contains("Single/Multiplayer: " + mode),
              lines.contains("Civilisation Set: Age of Empires II"),
              let dataset = lines.first(where: { $0.hasPrefix("Data Mod: ") }),
              Self.standardDataMods.contains(String(dataset.dropFirst("Data Mod: ".count))),
              let when = lines.first(where: { $0.hasPrefix("When game started: ") }),
              let minute = Self.date(String(when.dropFirst("When game started: ".count)), format: "HH:mm yyyy/MM/dd"),
              (0..<60).contains(created.timeIntervalSince(minute)),
              let siblings = try? FileManager.default.contentsOfDirectory(atPath: recording.deletingLastPathComponent().path)
        else { return nil }
        // Rapid rematches may share even the printed minute. Suppress metadata that
        // could also belong to another recorded start within this short write window.
        let otherNames = siblings.filter { $0 != recording.lastPathComponent && $0.hasPrefix("SP Replay ") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'@'yyyy.MM.dd HHmm"
        let minutePrefixes = [-tolerance, 0, tolerance].map { formatter.string(from: created.addingTimeInterval($0)) }
        guard !otherNames.contains(where: { name in
            guard minutePrefixes.contains(where: { name.contains($0) }),
                  let other = Self.recordingDetails(name) else { return false }
            return abs(other.start.timeIntervalSince(created)) <= tolerance
        }) else { return nil }
        return Self.singleplayerCivilization(lines)
    }

    private static func singleplayerCivilization(_ lines: [String]) -> String? {
        guard lines.last(where: { !$0.isEmpty }) == "}",
              let countLine = lines.first(where: { $0.hasPrefix("Number of Players: ") }),
              let count = Int(countLine.dropFirst("Number of Players: ".count)), (1...8).contains(count)
        else { return nil }
        var players = [Int: [String: String]]()
        var current: Int?
        for line in lines {
            if line.hasPrefix("Player "), line.hasSuffix(":") {
                guard let slot = Int(line.dropFirst(7).dropLast()), (1...8).contains(slot), players[slot] == nil else { return nil }
                current = slot
                players[slot] = [:]
            } else if let current, let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                if ["Humanity", "Civilization", "Name"].contains(key) {
                    guard players[current]?[key] == nil else { return nil }
                    players[current]?[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        guard players.count == count,
              players.values.allSatisfy({ ["Human", "AI"].contains($0["Humanity"]) }) else { return nil }
        let humans = players.values.filter { $0["Humanity"] == "Human" }
        guard humans.count == 1, let raw = humans.first?["Civilization"] else { return nil }
        return CivilizationCatalog.resolve(raw)?.id
    }

    static func gameWritableFiles() -> [RecordingWriter] {
        let games = NSRunningApplication.runningApplications(withBundleIdentifier: "com.feralinteractive.ageofempires2")
        guard games.count == 1, let game = games.first, !game.isTerminated else { return [] }
        return writableFiles(pid: game.processIdentifier)
    }

    static func writableFiles(pid: pid_t) -> [RecordingWriter] {
        let size = MemoryLayout<proc_fdinfo>.stride
        let estimate = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard estimate > 0 else { return [] }
        var descriptors = Array(repeating: proc_fdinfo(), count: Int(estimate) / size + 32)
        let bytes = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0, Int(bytes) < descriptors.count * size else { return [] }
        return descriptors.prefix(Int(bytes) / size).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            return recordingWriter(pid: pid, fd: descriptor.proc_fd)
        }
    }

    private static func recordingWriter(pid: pid_t, fd: Int32) -> RecordingWriter? {
        var info = vnode_fdinfowithpath()
        let length = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &info, length) == length,
              info.pfi.fi_openflags & UInt32(FWRITE) != 0 else { return nil }
        let inode = info.pvip.vip_vi.vi_stat.vst_ino
        let device = dev_t(bitPattern: info.pvip.vip_vi.vi_stat.vst_dev)
        return withUnsafeBytes(of: &info.pvip.vip_path) { bytes -> RecordingWriter? in
            let path = String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            guard path.hasSuffix(".aoe2record") else { return nil }
            return RecordingWriter(url: URL(fileURLWithPath: path).standardizedFileURL,
                                   device: device, inode: inode, pid: pid, fd: fd)
        }
    }
}
