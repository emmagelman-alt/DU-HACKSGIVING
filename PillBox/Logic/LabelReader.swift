import UIKit
import Vision

/// Reads the text on a label photo with Apple's Vision framework. Everything stays on the phone.
enum LabelReader {
    static func readLines(from image: UIImage) async throws -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            // Drug names aren't dictionary words; listing them stops "correction" into ordinary words.
            request.customWords = KnownDrugs.displayNames + KnownDrugs.names
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            try handler.perform([request])
            let observations = request.results ?? []
            // Top to bottom, then left to right (Vision's origin is bottom-left).
            let sorted = observations.sorted { a, b in
                abs(a.boundingBox.midY - b.boundingBox.midY) > 0.012
                    ? a.boundingBox.midY > b.boundingBox.midY
                    : a.boundingBox.minX < b.boundingBox.minX
            }
            return sorted.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
