import AppKit
import SwiftUI

/// a floating panel that takes the keyboard without stealing focus from the app you're in
final class Panel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

final class PanelController {
    enum Mode { case clips, emoji }

    let panel = Panel()
    private(set) var mode: Mode?
    private(set) var previous: NSRunningApplication?
    private var keys: ((NSEvent) -> Bool)?
    private var monitor: Any?
    var onSettings: (() -> Void)?

    /// there's no edit menu in a menu bar app, so do the text field shortcuts by hand
    private static let edits: [String: Selector] = [
        "a": #selector(NSText.selectAll(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)),
        "z": Selector(("undo:")),
    ]

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 { // esc
                self.hide()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers == "," {
                self.hide()
                self.onSettings?()
                return nil
            }
            if self.keys?(event) == true { return nil }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let ch = event.charactersIgnoringModifiers,
               let action = Self.edits[ch] {
                NSApp.sendAction(action, to: nil, from: nil)
                return nil
            }
            return event
        }
    }

    func isShowing(_ mode: Mode) -> Bool {
        panel.isVisible && self.mode == mode
    }

    func show<V: View>(_ mode: Mode, _ view: V, size: CGSize, keys: @escaping (NSEvent) -> Bool) {
        if !panel.isVisible { previous = NSWorkspace.shared.frontmostApplication }
        self.mode = mode
        self.keys = keys
        panel.contentView = NSHostingView(rootView: view)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.6 - size.height / 2,
                width: size.width,
                height: size.height
            ), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
        mode = nil
    }
}
