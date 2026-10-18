import Foundation
import Vision

/// reads the words in pictures and guesses what's in them, so you can search for them.
enum Seer {
    private static let q = DispatchQueue(label: "party.chee.clipcat.vision", qos: .utility)

    static func look(at path: String, id: Int64) {
        q.async {
            let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
            let read = VNRecognizeTextRequest()
            read.recognitionLevel = .accurate
            read.usesLanguageCorrection = true
            let guess = VNClassifyImageRequest()
            try? handler.perform([read, guess])

            let text = (read.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            let labels = (guess.results ?? [])
                .filter { $0.confidence > 0.35 }
                .prefix(6)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                .joined(separator: ", ")

            Store.shared.setVision(id, text: text, labels: labels)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .clipsChanged, object: nil)
            }
        }
    }

    static func catchUp() {
        DispatchQueue.global(qos: .utility).async {
            for clip in Store.shared.unseen() { look(at: clip.path, id: clip.id) }
        }
    }
}
