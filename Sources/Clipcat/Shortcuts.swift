import AppKit
import Carbon
import SwiftUI

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// carbon modifier flags (cmdKey, controlKey…)
    var modifiers: UInt32
    var key: String

    static let clips = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | controlKey), key: "C")
    static let emoji = Shortcut(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey | controlKey), key: "E")

    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    private static let names: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// nil unless it has ⌃, ⌥ or ⌘, so a bare letter can't get swallowed everywhere
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        guard mods != 0 else { return nil }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let key = Self.names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

/// the shortcuts, saved in user defaults
final class Shortcuts: ObservableObject {
    enum Which: String { case clips, emoji }

    @Published private(set) var clips: Shortcut
    @Published private(set) var emoji: Shortcut
    @Published var recording: Which? { didSet { onRecording?(recording != nil) } }
    /// off unless you turn it on. ⌘, in either overlay gets you back here.
    @Published var menuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(menuBarIcon, forKey: "showMenuBarIcon")
            onMenuBarIcon?(menuBarIcon)
        }
    }
    var onChange: (() -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onMenuBarIcon: ((Bool) -> Void)?

    init() {
        clips = Self.load(.clips) ?? .clips
        emoji = Self.load(.emoji) ?? .emoji
        menuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
    }

    subscript(which: Which) -> Shortcut {
        which == .clips ? clips : emoji
    }

    func set(_ which: Which, _ shortcut: Shortcut) {
        switch which {
        case .clips: clips = shortcut
        case .emoji: emoji = shortcut
        }
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "shortcut." + which.rawValue)
        }
        onChange?()
    }

    func reset() {
        set(.clips, .clips)
        set(.emoji, .emoji)
    }

    /// while recording, every key press goes here instead of the text field
    func record(_ event: NSEvent) -> Bool {
        guard let which = recording else { return false }
        if event.keyCode == 53 { // esc
            recording = nil
            return true
        }
        guard let shortcut = Shortcut(event: event) else {
            NSSound.beep()
            return true
        }
        recording = nil
        set(which, shortcut)
        return true
    }

    private static func load(_ which: Which) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: "shortcut." + which.rawValue) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}

struct SettingsView: View {
    @ObservedObject var shortcuts: Shortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("settings").font(Theme.font(18))

            row("clipboard", .clips)
            row("emoji", .emoji)

            Text(shortcuts.recording == nil
                 ? "click one, then press the new keys."
                 : "press the new keys. needs ⌃, ⌥ or ⌘. esc to cancel.")
                .font(Theme.font(11))
                .foregroundColor(Theme.quiet)

            HStack {
                Spacer()
                Chip(text: "reset")
                    .onTapGesture { shortcuts.reset() }
            }

            HStack {
                Text("menu bar icon").font(Theme.font(14))
                Spacer()
                button(shortcuts.menuBarIcon ? "on" : "off", on: shortcuts.menuBarIcon)
                    .onTapGesture { shortcuts.menuBarIcon.toggle() }
            }
        }
        .padding(20)
        .frame(width: 360)
        .foregroundColor(Theme.ink)
        .background(Theme.page)
    }

    private func row(_ title: String, _ which: Shortcuts.Which) -> some View {
        let on = shortcuts.recording == which
        return HStack {
            Text(title).font(Theme.font(14))
            Spacer()
            button(on ? "press keys…" : shortcuts[which].label, on: on)
                .onTapGesture { shortcuts.recording = on ? nil : which }
        }
    }

    private func button(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(Theme.font(14, on ? .bold : .regular))
            .foregroundColor(on ? .white : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 120)
            .boxy(on ? Theme.pink : Theme.card, line: on ? Theme.pinkDark : Theme.ink, lifted: on)
            .contentShape(Rectangle())
    }
}

/// a plain little window for the shortcuts
final class SettingsWindow {
    private var window: NSWindow?
    private var monitor: Any?
    private let shortcuts: Shortcuts

    init(shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if self.shortcuts.record(event) { return nil }
            if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") {
                window.close()
                return nil
            }
            return event
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "clipcat"
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView(shortcuts: shortcuts))
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in self?.shortcuts.recording = nil }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
