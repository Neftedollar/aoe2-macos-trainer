import CoreGraphics
import Foundation
import Vision

enum HUDTextParser {
    static func value(_ text: String, for field: HUDField) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if field == .clock {
            let pattern = #"\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b"#
            guard let range = cleaned.range(of: pattern, options: .regularExpression) else {
                return nil
            }
            let fields = cleaned[range].split(separator: ":").compactMap { Int($0) }
            if fields.count == 2, fields[1] < 60 {
                return fields[0] * 60 + fields[1]
            }
            if fields.count == 3, fields[1] < 60, fields[2] < 60 {
                return fields[0] * 3600 + fields[1] * 60 + fields[2]
            }
            return nil
        }

        let firstPart = cleaned.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let digits = firstPart.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let amount = Int(digits) else {
            return nil
        }
        if field == .villagers { return amount <= 300 ? amount : nil }
        return amount <= 999_999 ? amount : nil
    }
}

enum HUDRecognizer {
    static func read(image: CGImage, layout: HUDLayout) -> HUDSnapshot {
        var values: [HUDField: Int] = [:]
        for (field, region) in layout.regions where region.isValid {
            let pixelRect = CGRect(
                x: region.x * Double(image.width),
                y: region.y * Double(image.height),
                width: region.width * Double(image.width),
                height: region.height * Double(image.height)
            ).integral
            guard let cropped = image.cropping(to: pixelRect) else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
                let candidates = (request.results ?? []).flatMap { $0.topCandidates(3) }
                if let value = candidates.compactMap({ HUDTextParser.value($0.string, for: field) }).first {
                    values[field] = value
                }
            } catch {
                continue
            }
        }
        return HUDSnapshot(capturedAt: Date(), values: values)
    }
}
