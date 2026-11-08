import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TrainerAppDelegate: NSObject, NSApplicationDelegate {
    private let state = TrainerState()
    private var overlay: OverlayController?
    private var hotkeys: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var buildSubmenu: NSMenu?
    private var civilizationSubmenu: NSMenu?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlay = OverlayController(state: state)
        overlay.show()
        self.overlay = overlay

        configureMenu()

        hotkeys = HotkeyManager { [weak self] key in
            Task { @MainActor in self?.execute(key) }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state.tick() }
        }

        if let message = state.loadErrorMessage {
            showMessage("Не удалось загрузить каталог билдов", message)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
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

        let menu = NSMenu(title: "AoE2 Mac Trainer")
        addInfo("PREVIEW · нет подключения к текущему матчу", to: menu)
        addAction("Следующий шаг · ⌃⌥N", to: menu, selector: #selector(nextStep))
        addAction("Предыдущий шаг · ⌃⌥P", to: menu, selector: #selector(previousStep))
        addAction("Следующий PREVIEW-билд · ⌃⌥B", to: menu, selector: #selector(cyclePreviewBuild))
        addAction("Пауза / старт ручного таймера · ⌃⌥S", to: menu, selector: #selector(toggleClock))
        addAction("Сбросить тренировку · ⌃⌥R", to: menu, selector: #selector(reset))
        addAction("Показать / скрыть панель · ⌃⌥H", to: menu, selector: #selector(toggleOverlay))

        menu.addItem(.separator())
        let civMenu = NSMenu(title: "PREVIEW: цивилизация")
        civilizationSubmenu = civMenu
        populateCivilizationMenu()
        let civItem = NSMenuItem(title: "PREVIEW: выбрать цивилизацию вручную", action: nil, keyEquivalent: "")
        menu.addItem(civItem)
        menu.setSubmenu(civMenu, for: civItem)

        let submenu = NSMenu(title: "PREVIEW: подходящие билды")
        buildSubmenu = submenu
        populateBuildMenu()
        let buildsItem = NSMenuItem(title: "PREVIEW: подходящие билды", action: nil, keyEquivalent: "")
        menu.addItem(buildsItem)
        menu.setSubmenu(submenu, for: buildsItem)

        menu.addItem(.separator())
        let mapsMenu = NSMenu(title: "Создать локальный XS-мод каталога")
        addInfo("Все билды; настоящую цивилизацию определяет XS", to: mapsMenu)
        addAction("Arena…", to: mapsMenu, selector: #selector(createArenaMod))
        addAction("Arabia…", to: mapsMenu, selector: #selector(createArabiaMod))
        addAction("Nomad…", to: mapsMenu, selector: #selector(createNomadMod))
        mapsMenu.addItem(.separator())
        addAction("Из своего RMS-файла…", to: mapsMenu, selector: #selector(createModFromRMS))
        let mapsItem = NSMenuItem(title: "Создать локальный XS-мод каталога", action: nil, keyEquivalent: "")
        menu.addItem(mapsItem)
        menu.setSubmenu(mapsMenu, for: mapsItem)
        addAction("Экспорт всего каталога в XS…", to: menu, selector: #selector(exportXS))
        addAction("Открыть пользовательский JSON…", to: menu, selector: #selector(openCustomBuilds))
        addAction("Перезагрузить JSON-билды", to: menu, selector: #selector(reloadBuilds))

        menu.addItem(.separator())
        addAction("Выйти", to: menu, selector: #selector(quit))
        item.menu = menu
        statusItem = item
    }

    private func addAction(_ title: String, to menu: NSMenu, selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func addInfo(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
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
        let none = NSMenuItem(title: "Не выбрана — билды скрыты",
                              action: #selector(selectPreviewCivilization(_:)), keyEquivalent: "")
        none.target = self
        none.state = state.previewCivilizationID == nil ? .on : .off
        submenu.addItem(none)
        submenu.addItem(.separator())
        for civilization in CivilizationCatalog.standard {
            let count = BuildOrderLibrary.eligible(state.catalog, civilizationID: civilization.id).count
            let entry = NSMenuItem(title: "\(civilization.name) · билдов: \(count)",
                                  action: #selector(selectPreviewCivilization(_:)), keyEquivalent: "")
            entry.representedObject = civilization.id
            entry.target = self
            entry.state = state.previewCivilizationID == civilization.id ? .on : .off
            submenu.addItem(entry)
        }
    }

    private func populateBuildMenu() {
        guard let submenu = buildSubmenu else { return }
        submenu.removeAllItems()
        if state.builds.isEmpty {
            let message = state.previewCivilizationID == nil
                ? "Сначала выбери PREVIEW-цивилизацию"
                : "Для этой цивилизации нет подходящих билдов"
            addInfo(message, to: submenu)
            return
        }
        for (index, build) in state.builds.enumerated() {
            let entry = NSMenuItem(title: "\(build.name) · \(build.map)",
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
                        state.loadErrorMessage ?? "Исправь JSON и перезагрузи каталог. Выбирать PREVIEW-цивилизацию для экспорта не требуется.")
            return false
        }
        return true
    }

    private func createMod(source: TrainingModPackager.MapSource) {
        guard ensureCatalogAvailable() else { return }
        guard let folder = localModFolder() else { return }
        do {
            let location = try TrainingModPackager.install(
                catalog: state.catalog, preferredBuildID: state.selectedBuild?.id,
                source: source, into: folder
            )
            UserDefaults.standard.set(folder.path, forKey: "AoE2Trainer.localModsFolder")
            NSWorkspace.shared.activateFileViewerSelecting([location])
            let alert = NSAlert()
            alert.messageText = "Локальный XS-мод каталога создан"
            alert.informativeText = "\(location.path)\n\nПерезапусти AoE2, включи мод в Mods → My Mods / Installed Mods, затем Skirmish → Custom Map.\n\nВ мод включён весь каталог. XS определяет реальную цивилизацию в игре и выбирает совместимый билд. Хоткеи приложения переключают только PREVIEW и не отправляют команды в XS. Загрузка в нативной версии AoE2 для Mac ещё требует проверки."
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
                                                      preferredBuildID: state.selectedBuild?.id)
            let panel = NSSavePanel()
            panel.title = "Сохранить XS-модуль тренера"
            panel.nameFieldStringValue = "aoe2trainer_catalog.xs"
            panel.message = "Экспортируется весь исходный каталог, включая условия цивилизаций. Добавь #includeXS <имя файла> в свою RMS-карту. XS выбирает цивилизацию внутри игры; хоткеи оверлея управляют только PREVIEW.\n\n" + XSBuildExporter.textEncodingNotice
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
}

@main
struct AoE2TrainerApp: App {
    @NSApplicationDelegateAdaptor(TrainerAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
