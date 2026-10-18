import AppKit
import ApplicationServices

enum Paster {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        guard !trusted, !UserDefaults.standard.bool(forKey: "askedForAccess") else { return }
        UserDefaults.standard.set(true, forKey: "askedForAccess")
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func write(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.kind {
        case .text, .color:
            pb.setString(clip.body, forType: .string)
        case .link:
            pb.setString(clip.body, forType: .string)
            if let url = URL(string: clip.body.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pb.setString(url.absoluteString, forType: .URL)
            }
        case .file:
            pb.writeObjects(clip.body.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) })
        case .image:
            guard let path = clip.image, let data = FileManager.default.contents(atPath: path) else { return }
            pb.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
    }

    /// links in the browser, files and pictures in finder
    static func open(_ clip: Clip) {
        switch clip.kind {
        case .link:
            var text = clip.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("www.") { text = "https://" + text }
            if let url = URL(string: text) { NSWorkspace.shared.open(url) }
        case .file:
            let urls = clip.body.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .image:
            if let path = clip.image { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        case .text, .color:
            break
        }
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// presses ⌘V in the app you were in
    static func paste(into app: NSRunningApplication?) {
        send(into: app) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// types the string straight in, leaving the clipboard alone
    static func type(_ string: String, into app: NSRunningApplication?) {
        send(into: app) {
            let source = CGEventSource(stateID: .combinedSessionState)
            var units = Array(string.utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private static func send(into app: NSRunningApplication?, _ body: @escaping () -> Void) {
        app?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: body)
    }
}
