import AppKit
import ImageIO
import SwiftUI

/// boxy and bright: thick ink lines, square corners, hard offset shadows, candy colours.
enum Theme {
    static let ink = Color(hex: 0x1B1428)
    static let paper = Color(hex: 0xFFF8EC)
    static let card = Color.white
    static let pink = Color(hex: 0xFF4FA3)
    static let lemon = Color(hex: 0xFFE34D)
    static let mint = Color(hex: 0x4DEBB0)
    static let sky = Color(hex: 0x5CC8FF)
    static let lilac = Color(hex: 0xB59BFF)
    static let line: CGFloat = 3

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let bunny = "₍ᐢ•ﻌ•ᐢ₎"
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct Boxy: ViewModifier {
    let fill: Color
    let shadow: CGFloat

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: Theme.line))
            .background(Rectangle().fill(Theme.ink).offset(x: shadow, y: shadow))
    }
}

extension View {
    func boxy(_ fill: Color, shadow: CGFloat = 0) -> some View {
        modifier(Boxy(fill: fill, shadow: shadow))
    }
}

struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.font(10, .heavy))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
    }
}

struct Rule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(width: vertical ? Theme.line : nil, height: vertical ? nil : Theme.line)
    }
}

/// the frame both panels share: a title bar, a search box, the stuff, a footer.
struct Shell<Content: View>: View {
    let title: String
    let color: Color
    @Binding var query: String
    let placeholder: String
    let footer: String
    let content: Content
    @FocusState private var focused: Bool

    init(
        title: String,
        color: Color,
        query: Binding<String>,
        placeholder: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.color = color
        self._query = query
        self.placeholder = placeholder
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(Theme.font(15, .black))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color)
            Rule()
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(Theme.font(20))
                .tint(Theme.pink)
                .padding(12)
                .focused($focused)
            Rule()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rule()
            HStack {
                Text(footer).font(Theme.font(11)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.lemon)
        }
        .foregroundColor(Theme.ink)
        .boxy(Theme.paper, shadow: 8)
        .padding(EdgeInsets(top: 4, leading: 4, bottom: 12, trailing: 12))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

enum Ago {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func say(_ date: Date) -> String {
        -date.timeIntervalSinceNow < 45 ? "now" : formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// small decoded thumbnails, so a long history of screenshots doesn't eat memory
enum Thumbs {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 300
        return c
    }()

    static func get(_ path: String, size: Int) -> NSImage? {
        let key = "\(size):\(path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: key)
        return image
    }
}
