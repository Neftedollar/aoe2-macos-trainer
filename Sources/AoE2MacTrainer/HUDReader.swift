import AppKit
import Combine
import CoreGraphics
import ScreenCaptureKit

enum HUDCaptureError: LocalizedError {
    case requiresNewerMacOS
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .requiresNewerMacOS: "Захват HUD требует macOS 14 или новее."
        case .noDisplay: "Не удалось найти экран для захвата."
        }
    }
}

enum HUDScreenCapture {
    static func snapshot() async throws -> CGImage {
        guard #available(macOS 14.0, *) else {
            throw HUDCaptureError.requiresNewerMacOS
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        let preferredID = (NSScreen.main?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == preferredID })
                ?? content.displays.first else {
            throw HUDCaptureError.noDisplay
        }

        // Never record this app's own overlay or calibration window.
        let excluded = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excluded,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}

@MainActor
final class HUDReader: ObservableObject {
    @Published private(set) var snapshot: HUDSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isRunning = false

    private(set) var layout = HUDLayout.load()
    private var pollingTask: Task<Void, Never>?

    func capturePreview() async throws -> NSImage {
        let screenshot = try await HUDScreenCapture.snapshot()
        return NSImage(
            cgImage: screenshot,
            size: NSSize(width: screenshot.width, height: screenshot.height)
        )
    }

    func apply(_ newLayout: HUDLayout) {
        let wasRunning = isRunning
        stop()
        layout = newLayout
        layout.save()
        if wasRunning || layout.hasRegions { start() }
    }

    func start() {
        guard !isRunning, layout.hasRegions else { return }
        isRunning = true
        lastError = nil
        UserDefaults.standard.set(true, forKey: "HUDReader.enabled")
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        snapshot = nil
        UserDefaults.standard.set(false, forKey: "HUDReader.enabled")
    }

    private func pollOnce() async {
        do {
            let image = try await HUDScreenCapture.snapshot()
            let selectedLayout = layout
            let result = await Task.detached(priority: .utility) {
                HUDRecognizer.read(image: image, layout: selectedLayout)
            }.value
            if !Task.isCancelled {
                snapshot = result
                lastError = result.values.isEmpty ? "OCR: числа не найдены, проверь области HUD" : nil
            }
        } catch {
            if !Task.isCancelled { lastError = error.localizedDescription }
        }
    }
}
