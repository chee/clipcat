import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watcher = Watcher()
    private let panel = PanelController()
    private let clips = ClipModel()
    private let emoji = EmojiModel()
    private var hotKeys: [HotKey] = []
    private let shortcuts = Shortcuts()
    private lazy var settings = SettingsWindow(shortcuts: shortcuts)
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

        shortcuts.onChange = { [weak self] in self?.bindKeys() }
        // let go of the hotkeys while recording, or they'd swallow the very keys being pressed
        shortcuts.onRecording = { [weak self] recording in
            if recording { self?.hotKeys = [] } else { self?.bindKeys() }
        }
        panel.onSettings = { [weak self] in self?.settings.show() }
        bindKeys()

        NotificationCenter.default.addObserver(forName: .clipsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.panel.isShowing(.clips) else { return }
            self.clips.refresh(keep: true)
        }

        shortcuts.onMenuBarIcon = { [weak self] on in self?.showMenuBarIcon(on) }
        showMenuBarIcon(shortcuts.menuBarIcon)
        Paster.askForAccess()
    }

    private func bindKeys() {
        let clips = shortcuts.clips
        let emoji = shortcuts.emoji
        hotKeys = []
        hotKeys = [
            HotKey(keyCode: clips.keyCode, modifiers: clips.modifiers) { [weak self] in self?.toggle(.clips) },
            HotKey(keyCode: emoji.keyCode, modifiers: emoji.modifiers) { [weak self] in self?.toggle(.emoji) },
        ]
        updateMenu()
    }

    private func toggle(_ mode: PanelController.Mode) {
        if panel.isShowing(mode) {
            panel.hide()
            return
        }
        switch mode {
        case .clips:
            watcher.check()
            clips.filter = .all
            clips.query = ""
            panel.show(.clips, ClipsView(model: clips), size: CGSize(width: 924, height: 600), keys: clips.handle)
        case .emoji:
            emoji.filter = .all
            emoji.query = ""
            panel.show(.emoji, EmojiView(model: emoji), size: CGSize(width: 616, height: 580), keys: emoji.handle)
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

    private func showMenuBarIcon(_ on: Bool) {
        if !on {
            if let status { NSStatusBar.system.removeStatusItem(status) }
            status = nil
            return
        }
        guard status == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "=^.^="
        item.button?.font = NSFontManager.shared.font(withFamily: "Iosevka Rabbits", traits: [], weight: 5, size: 13)
            ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        item.button?.setAccessibilityLabel("clipcat")
        status = item
        updateMenu()
    }

    private func updateMenu() {
        guard let item = status else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "clipboard  " + shortcuts.clips.label, action: #selector(showClips), keyEquivalent: "").target = self
        menu.addItem(withTitle: "emoji  " + shortcuts.emoji.label, action: #selector(showEmoji), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if !Paster.trusted {
            menu.addItem(withTitle: "allow pasting…", action: #selector(allowPasting), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "quit clipcat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    @objc private func showClips() { toggle(.clips) }
    @objc private func showEmoji() { toggle(.emoji) }
    @objc private func showSettings() { settings.show() }
    @objc private func allowPasting() { Paster.openAccessSettings() }
}
