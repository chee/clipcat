import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watcher = Watcher()
    private let panel = PanelController()
    private let clips = ClipModel()
    private let emoji = EmojiModel()
    private var hotKeys: [HotKey] = []
    private var status: NSStatusItem?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // keep app nap from pausing the clipboard watcher
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "watching the clipboard"
        )
        watcher.start()
        Seer.catchUp()
        DispatchQueue.main.async { [emoji] in emoji.warm() }

        clips.onPick = { [weak self] clip, paste in self?.pick(clip, paste: paste) }
        emoji.onPick = { [weak self] emoji, type in self?.pick(emoji, type: type) }

        let mods = UInt32(cmdKey | controlKey)
        hotKeys = [
            HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: mods) { [weak self] in self?.toggle(.clips) },
            HotKey(keyCode: UInt32(kVK_ANSI_E), modifiers: mods) { [weak self] in self?.toggle(.emoji) },
        ]

        NotificationCenter.default.addObserver(forName: .clipsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.panel.isShowing(.clips) else { return }
            self.clips.refresh(keep: true)
        }

        if !UserDefaults.standard.bool(forKey: "hideMenuBarIcon") { setUpStatus() }
        Paster.askForAccess()
    }

    private func toggle(_ mode: PanelController.Mode) {
        if panel.isShowing(mode) {
            panel.hide()
            return
        }
        switch mode {
        case .clips:
            watcher.check()
            clips.query = ""
            panel.show(.clips, ClipsView(model: clips), size: CGSize(width: 820, height: 520), keys: clips.handle)
        case .emoji:
            emoji.query = ""
            panel.show(.emoji, EmojiView(model: emoji), size: CGSize(width: 540, height: 480), keys: emoji.handle)
        }
    }

    private func pick(_ clip: Clip, paste: Bool) {
        Paster.write(clip)
        Store.shared.touch(clip.id)
        panel.hide()
        if paste && Paster.trusted { Paster.paste(into: panel.previous) }
    }

    private func pick(_ emoji: Emoji, type: Bool) {
        self.emoji.remember(emoji)
        panel.hide()
        if type && Paster.trusted {
            Paster.type(emoji.char, into: panel.previous)
        } else {
            Paster.copy(emoji.char)
        }
    }

    private func setUpStatus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "clipcat")
        let menu = NSMenu()
        menu.addItem(withTitle: "clipboard  ⌃⌘V", action: #selector(showClips), keyEquivalent: "").target = self
        menu.addItem(withTitle: "emoji  ⌃⌘E", action: #selector(showEmoji), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if !Paster.trusted {
            menu.addItem(withTitle: "allow pasting…", action: #selector(allowPasting), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "quit clipcat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        status = item
    }

    @objc private func showClips() { toggle(.clips) }
    @objc private func showEmoji() { toggle(.emoji) }
    @objc private func allowPasting() { Paster.openAccessSettings() }
}
