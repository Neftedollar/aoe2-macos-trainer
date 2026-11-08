import Foundation

/// Creates a self-contained LOCAL training map mod. It never edits the game
/// installation or an existing mod. AoE2 loads XS only when an RMS references it.
enum TrainingModPackager {
    enum MapSource {
        case includedGameMap(String)
        case selectedRMS(URL)
    }

    enum PackageError: LocalizedError {
        case unsupportedMap
        case invalidMapFile
        case sourceAlreadyIncludesXS
        case targetAlreadyExists

        var errorDescription: String? {
            switch self {
            case .unsupportedMap:
                return "Для этой карты не указан стандартный RMS-файл. Выбери «Создать мод из своего RMS…» или добавь mapScriptFile в JSON."
            case .invalidMapFile:
                return "Некорректное имя RMS: допустимы только имена файлов с расширением .rms без путей и кавычек."
            case .sourceAlreadyIncludesXS:
                return "Исходная RMS уже подключает XS. Объединение нескольких XS с функцией main требует ручной проверки."
            case .targetAlreadyExists:
                return "Не удалось подобрать свободное имя папки мода. Существующие моды не перезаписываются."
            }
        }
    }

    static func builtinMap(for build: BuildOrder) -> MapSource? {
        if let file = build.mapScriptFile {
            return .includedGameMap(file)
        }
        switch build.map.lowercased() {
        case "аравия", "arabia": return .includedGameMap("Arabia.rms")
        case "арена", "arena": return .includedGameMap("Arena.rms")
        case "кочевник", "nomad": return .includedGameMap("Nomad.rms")
        default: return nil
        }
    }

    /// macOS Feral's virtual user directory mirrors the Windows game's profile.
    /// Return only existing profiles; don't guess a Steam account ID.
    static func detectedLocalModFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let profileRoot = home.appendingPathComponent(
            "Library/Application Support/Feral Interactive/Age Of Empires II/VFS/User/Games/Age of Empires 2 DE",
            isDirectory: true
        )
        let manager = FileManager.default
        let profiles = (try? manager.contentsOfDirectory(
            at: profileRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return profiles.filter { item in
            (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
                !item.lastPathComponent.isEmpty &&
                item.lastPathComponent.allSatisfy(\.isNumber)
        }.map {
            $0.appendingPathComponent("mods/local", isDirectory: true)
        }.sorted { $0.path < $1.path }
    }

    static func install(build: BuildOrder, source: MapSource,
                        into localModsFolder: URL,
                        fileManager: FileManager = .default) throws -> URL {
        try install(catalog: [build], preferredBuildID: build.id, source: source,
                    into: localModsFolder, fileManager: fileManager)
    }

    /// The complete catalog, not the resolved desktop preview, is exported.
    /// XS will choose eligible plans using the actual in-game civilization.
    static func install(catalog: [BuildOrder], preferredBuildID: String? = nil,
                        source: MapSource, into localModsFolder: URL,
                        fileManager: FileManager = .default) throws -> URL {
        let script = try XSBuildExporter.generate(builds: catalog, preferredBuildID: preferredBuildID)
        let mapExtension: String
        let sourceName: String
        switch source {
        case .includedGameMap(let file):
            mapExtension = "rms"
            sourceName = String(file.dropLast(".rms".count))
        case .selectedRMS(let file):
            mapExtension = file.pathExtension.lowercased()
            sourceName = file.deletingPathExtension().lastPathComponent
        }

        // AoE2 merges resources from enabled mods. Give each installation its
        // own XS name so enabling two catalogs cannot silently substitute the
        // higher-priority mod's script, even when they wrap the same map.
        let rawSlug = sourceName.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let slug = rawSlug.isEmpty ? "custom" : String(rawSlug.prefix(48))
        let instance = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let xsFile = "aoe2trainer_\(slug)_\(instance).xs"
        let mapContent = try makeMapContents(source: source, xsFilename: xsFile)

        // The generated directory is uniquely named; no existing mod is changed.
        let modBase = "AoE2Trainer_\(slug)"
        try fileManager.createDirectory(at: localModsFolder, withIntermediateDirectories: true)
        var modURL: URL?
        for index in 1...999 {
            let suffix = index == 1 ? "" : "_\(index)"
            let candidate = localModsFolder.appendingPathComponent(modBase + suffix, isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                modURL = candidate
                break
            }
        }
        guard let target = modURL else { throw PackageError.targetAlreadyExists }

        let staging = localModsFolder.appendingPathComponent(
            ".aoe2trainer-staging-\(UUID().uuidString)", isDirectory: true
        )
        do {
            let xsFolder = staging.appendingPathComponent("resources/_common/xs", isDirectory: true)
            let mapsFolder = staging.appendingPathComponent("resources/_common/random-map-scripts", isDirectory: true)
            try fileManager.createDirectory(at: xsFolder, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: mapsFolder, withIntermediateDirectories: true)

            try script.write(to: xsFolder.appendingPathComponent(xsFile), atomically: true, encoding: .utf8)
            try mapContent.write(to: mapsFolder.appendingPathComponent(target.lastPathComponent + ".\(mapExtension)"), options: .atomic)

            let manifest: [String: Any] = [
                "Title": "AoE2 Trainer – \(sourceName) – Catalog",
                "Author": "AoE2 Mac Trainer",
                "Description": "XS training catalog (\(catalog.count) builds). The game detects your civilization and filters eligible plans. External overlay hotkeys are preview-only.",
                "CacheStatus": 0
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: staging.appendingPathComponent("info.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: target)
            return target
        } catch {
            // Cleanup only the exact UUID staging directory created by this call.
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    static func makeMapContents(source: MapSource, xsFilename: String) throws -> Data {
        let prefix = "#includeXS \(xsFilename)\n"
        switch source {
        case .includedGameMap(let gameFile):
            guard isSafeRMSName(gameFile) else { throw PackageError.invalidMapFile }
            return Data((prefix + "#include_drs \(gameFile)\n").utf8)

        case .selectedRMS(let file):
            guard ["rms", "rms2"].contains(file.pathExtension.lowercased()) else {
                throw PackageError.invalidMapFile
            }
            let original = try Data(contentsOf: file)
            let text = String(decoding: original, as: UTF8.self).lowercased()
            if text.contains("#includexs") { throw PackageError.sourceAlreadyIncludesXS }
            let bom = Data([0xEF, 0xBB, 0xBF])
            var result = Data()
            if original.starts(with: bom) {
                result.append(bom)
                result.append(Data(prefix.utf8))
                result.append(contentsOf: original.dropFirst(3))
            } else {
                result.append(Data(prefix.utf8))
                result.append(original)
            }
            return result
        }
    }

    private static func isSafeRMSName(_ file: String) -> Bool {
        file.lowercased().hasSuffix(".rms") && !file.isEmpty &&
            file.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") }
    }
}
