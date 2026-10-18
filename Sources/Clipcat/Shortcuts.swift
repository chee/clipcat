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
    @Published var startAtLogin: Bool {
        didSet { LaunchAgent.set(startAtLogin) }
    }
    var onChange: (() -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onMenuBarIcon: ((Bool) -> Void)?

    init() {
        clips = Self.load(.clips) ?? .clips
        emoji = Self.load(.emoji) ?? .emoji
        menuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        startAtLogin = LaunchAgent.enabled
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
    @ObservedObject var history: HistorySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings").font(Theme.font(18))

            heading("shortcuts")
            row("clipboard", .clips)
            row("emoji", .emoji)
            HStack {
                Text(shortcuts.recording == nil
                     ? "click one, then press the new keys."
                     : "press the new keys. needs ⌃, ⌥ or ⌘. esc to cancel.")
                    .font(Theme.font(11))
                    .foregroundColor(Theme.quiet)
                Spacer()
                Chip(text: "reset").onTapGesture { shortcuts.reset() }
            }

            heading("history", "\(history.count) clips · \(HistorySettings.size(history.bytes))")
            HStack(spacing: 6) {
                label("keep")
                Chip(text: "forever", on: history.draft.keep == nil)
                    .onTapGesture { history.draft.keep = nil }
                ForEach(Age.allCases, id: \.self) { age in
                    Chip(text: age.label, on: history.draft.keep == age)
                        .onTapGesture { history.draft.keep = age }
                }
            }
            HStack(spacing: 6) {
                label("at most")
                number($history.draft.maxItems)
                Text("clips").font(Theme.font(12))
                Spacer().frame(width: 10)
                number($history.draft.maxMB)
                Text("MB").font(Theme.font(12))
            }
            HStack {
                Text("pinned clips are always kept.")
                    .font(Theme.font(11))
                    .foregroundColor(Theme.quiet)
                Spacer()
                if history.draft != history.saved {
                    button(history.draftDeletes > 0 ? "save · deletes \(history.draftDeletes)" : "save", on: true)
                        .onTapGesture { history.save() }
                }
            }

            heading("clean up now")
            HStack(spacing: 6) {
                label("older than")
                ForEach(Age.allCases, id: \.self) { age in
                    Chip(text: age.label, on: history.cleanAge == age)
                        .onTapGesture { history.cleanAge = age }
                }
            }
            HStack(spacing: 6) {
                label("at least")
                ForEach(MinSize.allCases, id: \.self) { size in
                    Chip(text: size.label, on: history.cleanSize == size)
                        .onTapGesture { history.cleanSize = size }
                }
            }
            HStack {
                Spacer()
                button(
                    history.cleanCount == 0
                        ? "nothing to delete"
                        : history.armed
                        ? "really delete \(history.cleanCount)? click again"
                        : "delete \(history.cleanCount) clips · \(HistorySettings.size(history.cleanBytes))",
                    on: history.armed
                )
                .opacity(history.cleanCount == 0 ? 0.5 : 1)
                .onTapGesture { history.clean() }
            }

            heading("app")
            HStack {
                label("start at login")
                Spacer()
                button(shortcuts.startAtLogin ? "on" : "off", on: shortcuts.startAtLogin)
                    .onTapGesture { shortcuts.startAtLogin.toggle() }
            }
            HStack {
                label("menu bar icon")
                Spacer()
                button(shortcuts.menuBarIcon ? "on" : "off", on: shortcuts.menuBarIcon)
                    .onTapGesture { shortcuts.menuBarIcon.toggle() }
            }
        }
        .padding(20)
        .frame(width: 480)
        .foregroundColor(Theme.ink)
        .background(Theme.page)
    }

    private func heading(_ title: String, _ detail: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.font(12, .bold)).foregroundColor(Theme.pink)
            Spacer()
            Text(detail).font(Theme.font(11)).foregroundColor(Theme.quiet)
        }
        .padding(.top, 6)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).frame(width: 84, alignment: .leading)
    }

    private func row(_ title: String, _ which: Shortcuts.Which) -> some View {
        let on = shortcuts.recording == which
        return HStack {
            label(title)
            Spacer()
            button(on ? "press keys…" : shortcuts[which].label, on: on)
                .onTapGesture { shortcuts.recording = on ? nil : which }
        }
    }

    /// empty means no limit
    private func number(_ value: Binding<Int?>) -> some View {
        TextField("∞", text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { text in value.wrappedValue = Int(text.filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil } }
        ))
        .textFieldStyle(.plain)
        .font(Theme.font(13))
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 80)
        .boxy(Theme.card)
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

/// the launch agent `make install` writes. turning it off removes it; turning it on
/// writes it again, pointing at this copy of the app. launchd picks it up at login.
enum LaunchAgent {
    static let label = "party.chee.clipcat"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var enabled: Bool {
        (NSDictionary(contentsOf: url)?["RunAtLoad"] as? Bool) ?? false
    }

    static func set(_ on: Bool) {
        guard on else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let executable = Bundle.main.executablePath else { return }
        let plist: NSDictionary = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = plist.write(to: url, atomically: true)
    }
}

/// a plain little window for the shortcuts
final class SettingsWindow {
    private var window: NSWindow?
    private var monitor: Any?
    private let shortcuts: Shortcuts
    private let history = HistorySettings()

    init(shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if self.shortcuts.record(event) { return nil }
            if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") {
                window.close()
                return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let ch = event.charactersIgnoringModifiers, let action = PanelController.edits[ch] {
                NSApp.sendAction(action, to: nil, from: nil)
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
            let host = NSHostingView(rootView: SettingsView(shortcuts: shortcuts, history: history))
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in self?.shortcuts.recording = nil }
            self.window = window
        }
        history.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
