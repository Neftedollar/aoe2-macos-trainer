import AppKit
import SwiftUI

@MainActor
final class TrainerAppDelegate: NSObject, NSApplicationDelegate {
    private let state = TrainerState()
    private var overlay: OverlayController?
    private var hotkeys: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var buildSubmenu: NSMenu?
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
        addAction("Следующий шаг · ⌃⌥N", to: menu, selector: #selector(nextStep))
        addAction("Предыдущий шаг · ⌃⌥P", to: menu, selector: #selector(previousStep))
        addAction("Пауза / старт таймера · ⌃⌥S", to: menu, selector: #selector(toggleClock))
        addAction("Сбросить тренировку · ⌃⌥R", to: menu, selector: #selector(reset))
        addAction("Показать / скрыть панель · ⌃⌥H", to: menu, selector: #selector(toggleOverlay))

        menu.addItem(.separator())
        addAction("Создать локальный XS-мод…", to: menu, selector: #selector(createTrainingMod))
        addAction("Создать XS-мод из RMS-файла…", to: menu, selector: #selector(createModFromRMS))
        addAction("Экспорт XS для выбранного билда…", to: menu, selector: #selector(exportXS))
        addAction("Открыть пользовательский JSON…", to: menu, selector: #selector(openCustomBuilds))
        addAction("Перезагрузить JSON-билды", to: menu, selector: #selector(reloadBuilds))
        let submenu = NSMenu(title: "Билд-ордер")
        buildSubmenu = submenu
        populateBuildMenu()
        let buildsItem = NSMenuItem(title: "Выбрать билд-ордер", action: nil, keyEquivalent: "")
        menu.addItem(buildsItem)
        menu.setSubmenu(submenu, for: buildsItem)

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

    @objc private func nextStep() { state.next() }
    @objc private func previousStep() { state.previous() }
    @objc private func toggleClock() { state.toggleClock() }
    @objc private func toggleOverlay() { overlay?.toggle() }
    @objc private func reset() { state.reset() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func populateBuildMenu() {
        guard let submenu = buildSubmenu else { return }
        submenu.removeAllItems()
        for (index, build) in state.builds.enumerated() {
            let entry = NSMenuItem(title: "\(build.name) · \(build.civilization)",
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
            populateBuildMenu()
        } catch {
            showError("Ошибка в пользовательском builds.json", error)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func createTrainingMod() {
        guard let build = state.selectedBuild else { return }
        guard let source = TrainingModPackager.builtinMap(for: build) else {
            showError("У карты нет стандартного RMS-источника",
                      TrainingModPackager.PackageError.unsupportedMap)
            return
        }
        createMod(for: build, source: source)
    }

    @objc private func createModFromRMS() {
        guard let build = state.selectedBuild else { return }
        let panel = NSOpenPanel()
        panel.title = "Выбери исходную карту RMS"
        panel.message = "Мы создадим копию карты с подключённым XS. Исходный файл не изменится."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["rms", "rms2"]
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        createMod(for: build, source: .selectedRMS(selected))
    }

    private func createMod(for build: BuildOrder, source: TrainingModPackager.MapSource) {
        guard let folder = localModFolder() else { return }
        do {
            let location = try TrainingModPackager.install(
                build: build, source: source, into: folder
            )
            UserDefaults.standard.set(folder.path, forKey: "AoE2Trainer.localModsFolder")
            NSWorkspace.shared.activateFileViewerSelecting([location])
            let alert = NSAlert()
            alert.messageText = "Локальный мод создан"
            alert.informativeText = "\(location.path)\n\nВ игре: Mods → Installed Mods, затем Skirmish → Custom Map. Загрузка в нативной версии AoE2 для Mac ещё требует проверки."
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
        guard let build = state.selectedBuild else { return }
        do {
            let script = try XSBuildExporter.generate(for: build)
            let panel = NSSavePanel()
            panel.title = "Сохранить XS-модуль тренера"
            panel.nameFieldStringValue = XSBuildExporter.recommendedFileName(for: build)
            panel.message = "Для запуска в AoE2 добавь #includeXS <имя файла> в пользовательскую RMS-карту."
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
}

@main
struct AoE2TrainerApp: App {
    @NSApplicationDelegateAdaptor(TrainerAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
