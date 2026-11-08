import Foundation

enum TrainerResources {
    static let bundle: Bundle? = {
        let main = Bundle.main
        guard main.bundleURL.pathExtension == "app" else {
            // swift run and swift test use SwiftPM's build products directly.
            return Bundle.module
        }

        // The distributed .app carries the SwiftPM bundle in Contents/Resources.
        // Bundle.module can trap here before our startup error handler runs.
        let name = "AoE2MacTrainer_AoE2MacTrainer"
        guard let url = main.url(forResource: name, withExtension: "bundle") else { return nil }
        return Bundle(url: url)
    }()
}
