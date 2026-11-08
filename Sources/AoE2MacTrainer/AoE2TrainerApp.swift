import AppKit
import SwiftUI

@MainActor
final class TrainerAppDelegate: NSObject, NSApplicationDelegate {
    private let state = TrainerState()
    private var overlay: OverlayController?
    private var hotkeys: HotkeyManager?
    private var statusItem: NSStatusItem?
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
        case .cycleBuild: state.cycleBuild()
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
        let submenu = NSMenu(title: "Билд-ордер")
        for (index, build) in state.builds.enumerated() {
            let buildItem = NSMenuItem(title: build.name, action: #selector(selectBuild(_:)), keyEquivalent: "")
            buildItem.tag = index
            buildItem.target = self
            submenu.addItem(buildItem)
        }
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

    @objc private func selectBuild(_ sender: NSMenuItem) {
        state.selectBuild(sender.tag)
    }
}

@main
struct AoE2TrainerApp: App {
    @NSApplicationDelegateAdaptor(TrainerAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
