import AppKit
import ImageIO
import SwiftUI

/// iosevka rabbits, thin black lines, tiny corners, hard little shadows that grow when
/// something is picked, and hot pink for the picked thing.
enum Theme {
    static let ink = Color(hex: 0x111111)
    static let page = Color(hex: 0xFDFFEC) // cream
    static let card = Color.white
    static let pink = Color(hex: 0xE34685)
    static let pinkDark = Color(hex: 0xB7376A)
    static let cherries = Color(hex: 0xFFE9ED)
    static let cherriesLine = Color(hex: 0xCC3366)
    static let yellow = Color(hex: 0xFFD807)
    static let teal = Color(hex: 0x64AFB1)
    static let mint = Color(hex: 0xAEEFEC)
    static let lavender = Color(hex: 0xD5D4EC)
    static let sky = Color(hex: 0x5AC8EE)
    static let quiet = Color(hex: 0x595959)
    static let radius: CGFloat = 2

    /// bundled in the app. falls back to the system mono.
    private static let family: String? = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return ["Iosevka Rabbits", "Iosevka"].first { installed.contains($0) }
    }()

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let family { return .custom(family, size: size).weight(weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }

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

/// a box with a 1px line and a hard shadow.
/// `lifted` is the hover state: a 2px shadow and nudged up-left by a pixel.
struct Boxy: ViewModifier {
    let fill: Color
    let line: Color
    let lifted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(line, lineWidth: 1))
            .background(shape.fill(line).offset(x: lifted ? 2 : 1, y: lifted ? 2 : 1))
            .offset(x: lifted ? -1 : 0, y: lifted ? -1 : 0)
    }
}

extension View {
    func boxy(_ fill: Color, line: Color = Theme.ink, lifted: Bool = false) -> some View {
        modifier(Boxy(fill: fill, line: line, lifted: lifted))
    }

    /// rows drift in one after another when the overlay opens
    func fadeIn(_ index: Int) -> some View {
        modifier(FadeIn(delay: index < 14 ? Double(index) * 0.022 : 0))
    }
}

struct FadeIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
            .onAppear { withAnimation(.easeOut(duration: 0.18).delay(delay)) { shown = true } }
    }
}

struct Chip: View {
    let text: String
    var fill: Color = Theme.card
    var on = false

    var body: some View {
        Text(text)
            .font(Theme.font(12, on ? .bold : .regular))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .boxy(on ? Theme.yellow : fill, lifted: on)
    }
}

struct Keycap: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Theme.font(11))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .boxy(Theme.card)
            Text(label).font(Theme.font(11)).foregroundColor(Theme.quiet)
        }
    }
}

struct Rule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// the overlay: a big search bar, filter chips, the results, and an action bar. like raycast.
struct Overlay<Content: View>: View {
    let placeholder: String
    @Binding var query: String
    let filters: [String]
    let filter: String
    let pickFilter: (String) -> Void
    let status: String
    let keys: [Keycap]
    let content: Content
    @FocusState private var focused: Bool

    init(
        placeholder: String,
        query: Binding<String>,
        filters: [String],
        filter: String,
        pickFilter: @escaping (String) -> Void,
        status: String,
        keys: [Keycap],
        @ViewBuilder content: () -> Content
    ) {
        self.placeholder = placeholder
        self._query = query
        self.filters = filters
        self.filter = filter
        self.pickFilter = pickFilter
        self.status = status
        self.keys = keys
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(22))
                    .tint(Theme.pink)
                    .focused($focused)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { name in
                        Chip(text: name, on: name == filter)
                            .onTapGesture { pickFilter(name) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 8)

            Rule()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rule()

            HStack(spacing: 12) {
                Text(status).font(Theme.font(11)).foregroundColor(Theme.quiet).lineLimit(1)
                Spacer(minLength: 8)
                ForEach(keys.indices, id: \.self) { keys[$0] }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.cherries)
        }
        .foregroundColor(Theme.ink)
        .background(Theme.page)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ink, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.ink).offset(x: 3, y: 3))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(EdgeInsets(top: 20, leading: 30, bottom: 40, trailing: 34))
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

    static func pixels(_ path: String) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}
