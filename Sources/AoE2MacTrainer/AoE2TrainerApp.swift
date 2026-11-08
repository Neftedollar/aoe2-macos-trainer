import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TrainerAppDelegate: NSObject, NSApplicationDelegate {
    private let state: TrainerState
    private var overlay: OverlayController?
    private var hotkeys: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var buildSubmenu: NSMenu?
    private var civilizationSubmenu: NSMenu?
    private var foodSubmenu: NSMenu?
    private var connectionItem: NSMenuItem?
    private var timer: Timer?
    private var matchObservation: Task<Void, Never>?
    private let logger = Logger(subsystem: "io.github.neftedollar.aoe2-macos-trainer", category: "match")

    override convenience init() {
        self.init(state: TrainerState())
    }

    init(state: TrainerState) {
        self.state = state
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let menuBarOnly = CommandLine.arguments.contains("--menu-bar-only")
        let overlay = OverlayController(state: state)
        if !menuBarOnly {
            overlay.show()
        }
        self.overlay = overlay

        configureMenu()
        matchObservation = Task.detached(priority: .utility) { [weak self] in
            let detector = FeralMatchDetector()
            while !Task.isCancelled {
                let match = detector.currentMatch()
                await self?.updateMatch(match)
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
            }
        }

        hotkeys = HotkeyManager { [weak self] key in
            Task { @MainActor in self?.execute(key) }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state.tick() }
        }

        if !menuBarOnly, let message = state.loadErrorMessage {
            showMessage("Не удалось загрузить каталог билдов", message)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        matchObservation?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay?.show()
        return false
    }

    private func execute(_ key: TrainerHotkey) {
        switch key {
        case .nextStep: state.next()
        case .previousStep: state.previous()
        case .cycleBuild:
            state.cycleBuild()
            populateBuildMenu()
        case .toggleClock: state.toggleClock()
        case .toggleOverlay: overlay?.toggle()
        case .reset: state.reset()
        }
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🏰"
        item.button?.toolTip = "AoE2 Mac Trainer"
        item.button?.setAccessibilityLabel("AoE2 Mac Trainer")
        item.menu = makeMenu()
        statusItem = item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "AoE2 Mac Trainer")
        connectionItem = addInfo(state.connectionTitle, to: menu)
        addAction("Следующий шаг · ⌃⌥N", to: menu, selector: #selector(nextStep))
        addAction("Предыдущий шаг · ⌃⌥P", to: menu, selector: #selector(previousStep))
        addAction("Следующий билд · ⌃⌥B", to: menu, selector: #selector(cyclePreviewBuild))
        addAction("Старт / пауза таймера · ⌃⌥S", to: menu, selector: #selector(toggleClock))
        addAction("Сбросить тренировку · ⌃⌥R", to: menu, selector: #selector(reset))
        addAction("Показать / скрыть панель · ⌃⌥H", to: menu, selector: #selector(toggleOverlay))

        menu.addItem(.separator())
        let civMenu = NSMenu(title: "Цивилизация")
        civilizationSubmenu = civMenu
        populateCivilizationMenu()
        let civItem = NSMenuItem(title: civMenu.title, action: nil, keyEquivalent: "")
        menu.addItem(civItem)
        menu.setSubmenu(civMenu, for: civItem)

        let foodMenu = NSMenu(title: "Дичь на старте")
        foodSubmenu = foodMenu
        populateFoodMenu()
        let foodItem = NSMenuItem(title: foodMenu.title, action: nil, keyEquivalent: "")
        menu.addItem(foodItem)
        menu.setSubmenu(foodMenu, for: foodItem)

        let submenu = NSMenu(title: "Подходящие билды")
        buildSubmenu = submenu
        populateBuildMenu()
        let buildsItem = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        menu.addItem(buildsItem)
        menu.setSubmenu(submenu, for: buildsItem)

        menu.addItem(.separator())
        let mapsMenu = NSMenu(title: "Создать тренировочную карту")
        addAction("Arena…", to: mapsMenu, selector: #selector(createArenaMod))
        addAction("Arabia…", to: mapsMenu, selector: #selector(createArabiaMod))
        addAction("Nomad…", to: mapsMenu, selector: #selector(createNomadMod))
        mapsMenu.addItem(.separator())
        addAction("Из своего RMS-файла…", to: mapsMenu, selector: #selector(createModFromRMS))
        let mapsItem = NSMenuItem(title: mapsMenu.title, action: nil, keyEquivalent: "")
        menu.addItem(mapsItem)
        menu.setSubmenu(mapsMenu, for: mapsItem)
        addAction("Экспорт всего каталога в XS…", to: menu, selector: #selector(exportXS))
        addAction("Открыть пользовательский JSON…", to: menu, selector: #selector(openCustomBuilds))
        addAction("Перезагрузить JSON-билды", to: menu, selector: #selector(reloadBuilds))

        menu.addItem(.separator())
        addAction("Выйти", to: menu, selector: #selector(quit))
        return menu
    }

    private func addAction(_ title: String, to menu: NSMenu, selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @discardableResult
    private func addInfo(_ title: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    func updateMatch(_ match: FeralMatch?) {
        guard match != state.match else { return }
        state.updateMatch(match)
        connectionItem?.title = state.connectionTitle
        refreshPreviewMenus()
        logger.notice("\(self.state.connectionTitle, privacy: .public)")
    }

    @objc private func nextStep() { state.next() }
    @objc private func previousStep() { state.previous() }
    @objc private func toggleClock() { state.toggleClock() }
    @objc private func toggleOverlay() { overlay?.toggle() }
    @objc private func reset() { state.reset() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func cyclePreviewBuild() {
        state.cycleBuild()
        populateBuildMenu()
    }

    private func populateCivilizationMenu() {
        guard let submenu = civilizationSubmenu else { return }
        submenu.removeAllItems()
        if state.match != nil {
            addInfo(state.previewCivilization?.name ?? "Не удалось определить игрока или цивилизацию", to: submenu)
            return
        }
        let none = NSMenuItem(title: "Не выбрана",
                              action: #selector(selectPreviewCivilization(_:)), keyEquivalent: "")
        none.target = self
        none.state = state.previewCivilizationID == nil ? .on : .off
        submenu.addItem(none)
        submenu.addItem(.separator())
        for civilization in CivilizationCatalog.standard {
            let count = BuildOrderLibrary.eligible(state.catalog, civilizationID: civilization.id,
                                                  startingFoodEvidence: state.previewFoodEvidence).count
            let entry = NSMenuItem(title: "\(civilization.name) · \(PreviewText.builds(count))",
                                  action: #selector(selectPreviewCivilization(_:)), keyEquivalent: "")
            entry.representedObject = civilization.id
            entry.target = self
            entry.state = state.previewCivilizationID == civilization.id ? .on : .off
            submenu.addItem(entry)
        }
    }

    private func populateFoodMenu() {
        guard let submenu = foodSubmenu else { return }
        submenu.removeAllItems()
        for kind in StartingFoodKind.allCases {
            let selectedCount = state.previewFoodEvidence.observedCount(for: kind)
            let selector: Selector = kind == .pushableHunt
                ? #selector(setPreviewPushableHuntCount(_:)) : #selector(setPreviewSmallGameCount(_:))
            let countMenu = NSMenu(title: kind.displayName)
            let largestRequirement = state.catalog.flatMap { $0.startingFoodRequirements ?? [] }
                .filter { $0.kind == kind }.map(\.minCount).max() ?? 0
            for count in 0...max(6, selectedCount, largestRequirement) {
                let entry = NSMenuItem(title: PreviewText.animals(count), action: selector, keyEquivalent: "")
                entry.tag = count
                entry.target = self
                entry.state = selectedCount == count ? .on : .off
                countMenu.addItem(entry)
            }
            let title = selectedCount == 0 ? kind.displayName : "\(kind.displayName) · \(selectedCount)"
            let kindItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            submenu.addItem(kindItem)
            submenu.setSubmenu(countMenu, for: kindItem)
        }
    }

    private func populateBuildMenu() {
        guard let submenu = buildSubmenu else { return }
        submenu.removeAllItems()
        if let message = state.loadErrorMessage {
            addInfo(message, to: submenu)
            submenu.addItem(.separator())
        }
        if let notice = state.selectionNotice {
            addInfo(notice, to: submenu)
            submenu.addItem(.separator())
        }
        if state.selectedBuild == nil, let requested = state.requestedBuildID {
            let title = state.unavailableRequestedBuild?.name ?? requested
            addInfo("Сейчас недоступен билд «\(title)»", to: submenu)
            submenu.addItem(.separator())
        }
        if state.builds.isEmpty {
            let message = state.previewCivilizationID == nil
                ? (state.match == nil ? "Сначала выбери цивилизацию" : "Ожидаем данные о цивилизации")
                : "Для этих условий подходящих билдов нет"
            addInfo(message, to: submenu)
            return
        }
        for (index, build) in state.builds.enumerated() {
            let family = build.strategyFamily.map { " · \($0)" } ?? ""
            let entry = NSMenuItem(title: "\(build.name) · \(build.map)\(family)",
                                   action: #selector(selectBuild(_:)), keyEquivalent: "")
            entry.tag = index
            entry.state = index == state.selectedBuildIndex ? .on : .off
            entry.target = self
            submenu.addItem(entry)
        }
    }

    @objc private func openCustomBuilds() {
        do {
            let url = try BuildOrderLibrary.prepareCustomBuildsFile()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError("Не удалось открыть JSON-билды", error)
        }
    }

    @objc private func reloadBuilds() {
        do {
            try state.reloadBuilds()
            populateCivilizationMenu()
            populateFoodMenu()
            populateBuildMenu()
        } catch {
            showMessage("Ошибка в пользовательском builds.json",
                        error.localizedDescription + "\n\nПредыдущий валидный каталог и выбор не изменены.")
        }
    }

    private func showError(_ title: String, _ error: Error) {
        showMessage(title, error.localizedDescription)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func createArenaMod() { createMod(source: .includedGameMap("Arena.rms")) }
    @objc private func createArabiaMod() { createMod(source: .includedGameMap("Arabia.rms")) }
    @objc private func createNomadMod() { createMod(source: .includedGameMap("Nomad.rms")) }

    @objc private func createModFromRMS() {
        guard ensureCatalogAvailable() else { return }
        let panel = NSOpenPanel()
        panel.title = "Выбери исходную карту RMS"
        panel.message = "Мы создадим копию карты с подключённым XS. Исходный файл не изменится."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["rms", "rms2"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        createMod(source: .selectedRMS(selected))
    }

    private func ensureCatalogAvailable() -> Bool {
        guard !state.catalog.isEmpty else {
            showMessage("Каталог билдов не загружен",
                        state.loadErrorMessage ?? "Исправь builds.json и перезагрузи каталог.")
            return false
        }
        return true
    }

    private func createMod(source: TrainingModPackager.MapSource) {
        guard ensureCatalogAvailable() else { return }
        guard let folder = localModFolder() else { return }
        do {
            let location = try TrainingModPackager.install(
                catalog: state.catalog, preferredBuildID: state.exportPreferredBuildID,
                source: source, into: folder
            )
            UserDefaults.standard.set(folder.path, forKey: "AoE2Trainer.localModsFolder")
            NSWorkspace.shared.activateFileViewerSelecting([location])
            let alert = NSAlert()
            alert.messageText = "Локальный XS-мод каталога создан"
            alert.informativeText = "Включи мод в «Моды → Установленные» и выбери «Своя карта → \(location.lastPathComponent)». Если карта не появилась, перезапусти игру.\n\nВ моде весь каталог. Выбранный билд получит приоритет, если подойдёт к цивилизации и дичи, которую XS обнаружит в матче.\n\n\(location.path)"
            alert.informativeText += "\n\n" + XSBuildExporter.textEncodingNotice
            alert.runModal()
        } catch {
            showError("Не удалось создать тренировочный мод", error)
        }
    }

    private func localModFolder() -> URL? {
        let manager = FileManager.default
        if let savedPath = UserDefaults.standard.string(forKey: "AoE2Trainer.localModsFolder"),
           manager.fileExists(atPath: savedPath) {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }
        let found = TrainingModPackager.detectedLocalModFolders()
        if found.count == 1 { return found[0] }

        let panel = NSOpenPanel()
        panel.title = "Папка для локальных модов AoE2"
        panel.message = "Выбери папку mods/local своего профиля AoE2. Если её пока нет, можно выбрать папку для экспорта и перенести мод позже."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = found.first?.deletingLastPathComponent() ??
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc private func exportXS() {
        guard ensureCatalogAvailable() else { return }
        do {
            let script = try XSBuildExporter.generate(builds: state.catalog,
                                                      preferredBuildID: state.exportPreferredBuildID)
            let panel = NSSavePanel()
            panel.title = "Сохранить XS-модуль тренера"
            panel.nameFieldStringValue = "aoe2trainer_catalog.xs"
            panel.message = "В файл войдёт весь каталог. Добавь #includeXS <имя файла> перед <PLAYER_SETUP> в своей RMS-карте. Цивилизацию и дичь XS определяет в матче.\n\n" + XSBuildExporter.textEncodingNotice
            if panel.runModal() == .OK, let url = panel.url {
                try script.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось экспортировать XS"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func selectBuild(_ sender: NSMenuItem) {
        state.selectBuild(sender.tag)
        populateBuildMenu()
    }

    @objc private func selectPreviewCivilization(_ sender: NSMenuItem) {
        state.selectPreviewCivilization(sender.representedObject as? String)
        populateCivilizationMenu()
        populateBuildMenu()
    }

    @objc private func setPreviewPushableHuntCount(_ sender: NSMenuItem) {
        state.updatePreviewFoodEvidence(StartingFoodEvidence(
            pushableHuntCount: sender.tag, smallGameCount: state.previewFoodEvidence.smallGameCount
        ))
        refreshPreviewMenus()
    }

    @objc private func setPreviewSmallGameCount(_ sender: NSMenuItem) {
        state.updatePreviewFoodEvidence(StartingFoodEvidence(
            pushableHuntCount: state.previewFoodEvidence.pushableHuntCount, smallGameCount: sender.tag
        ))
        refreshPreviewMenus()
    }

    private func refreshPreviewMenus() {
        populateFoodMenu()
        populateCivilizationMenu()
        populateBuildMenu()
    }
}

struct AoE2TrainerApp: App {
    @NSApplicationDelegateAdaptor(TrainerAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@main
enum TrainerEntryPoint {
    @MainActor static func main() {
        guard CommandLine.arguments.dropFirst().contains("--check-resources") else {
            AoE2TrainerApp.main()
            return
        }

        // Check the release artifact without starting AppKit or reading a user's custom builds.
        do {
            let catalog = try BuildOrderLibrary.bundled()
            let xs = try XSBuildExporter.generate(builds: catalog)
            print("Resource check OK (\(catalog.count) plans, \(xs.utf8.count) XS bytes)")
        } catch {
            let message = "Resource check failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}
