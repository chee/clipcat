import AppKit
import SwiftUI

extension Clip.Kind {
    var label: String {
        switch self {
        case .text: return "text"
        case .image: return "picture"
        case .file: return "file"
        case .link: return "link"
        case .color: return "colour"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .link: return "link"
        case .color: return "paintpalette"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Theme.cherries
        case .image: return Theme.mint
        case .file: return Theme.lavender
        case .link: return Theme.sky
        case .color: return Theme.yellow
        }
    }
}

extension Clip {
    var title: String {
        switch kind {
        case .text, .link, .color:
            return String(body.prefix(240)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        case .file:
            return body.split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)).lastPathComponent }
                .joined(separator: ", ")
        case .image:
            if let line = vision?.split(separator: "\n").first { return String(line) }
            if !labels.isEmpty { return labels }
            return vision == nil ? "looking…" : "a picture"
        }
    }

    var tags: [String] {
        labels.components(separatedBy: ", ").filter { !$0.isEmpty }
    }

    var swatch: Color? {
        Hex.parse(body).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
    }
}

/// the little square at the start of a row: a thumbnail, a swatch, a file icon or a symbol
struct ClipIcon: View {
    let clip: Clip
    let size: CGFloat

    var body: some View {
        Group {
            if let path = clip.image, let image = Thumbs.get(path, size: 96) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let swatch = clip.swatch {
                swatch
            } else if clip.kind == .file, let first = clip.body.split(separator: "\n").first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: String(first))).resizable().padding(2)
            } else {
                Image(systemName: clip.kind.symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(clip.kind.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, lineWidth: 1))
    }
}

struct ClipsView: View {
    @ObservedObject var model: ClipModel

    var body: some View {
        Overlay(
            placeholder: "search clips, words in pictures, @app…",
            query: $model.query,
            filters: ClipFilter.allCases.map(\.rawValue),
            filter: model.filter.rawValue,
            pickFilter: { model.filter = ClipFilter(rawValue: $0) ?? .all },
            status: "\(model.clips.count == 400 ? "400+" : String(model.clips.count)) clips",
            keys: [
                Keycap(key: "↩", label: "paste"),
                Keycap(key: "⌘↩", label: "copy"),
                Keycap(key: "⌘P", label: model.current?.pinned == true ? "unpin" : "pin"),
                Keycap(key: "⌘O", label: "open"),
                Keycap(key: "⌘⌫", label: "forget"),
                Keycap(key: "⇥", label: "filter"),
            ]
        ) {
            HStack(spacing: 0) {
                list.frame(width: 360)
                Rule(vertical: true)
                ClipPreview(clip: model.current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.card)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.clips.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.query.isEmpty && model.filter == .all ? "✂️  nothing yet." : "🔍  nothing matches.")
                            Text(model.query.isEmpty && model.filter == .all ? "🐇  copy something!" : "🐇  try fewer words, or ⇥ to another filter.")
                        }
                        .font(Theme.font(13))
                        .foregroundColor(Theme.pink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(clip: clip, index: index, selected: index == model.selected)
                            .fadeIn(index)
                            .onTapGesture(count: 2) { model.onPick?(clip, true) }
                            .onTapGesture { model.selected = index }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10))
            }
            .onChange(of: model.selected) { index in
                if model.clips.indices.contains(index) { proxy.scrollTo(model.clips[index].id) }
            }
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(clip: clip, size: 28)
            Text(clip.title)
                .font(Theme.font(13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if clip.pinned { Text("📌").font(.system(size: 11)) }
            Text(index < 9 ? "⌘\(index + 1)" : Ago.say(clip.used))
                .font(Theme.font(11))
                .foregroundColor(selected ? .white.opacity(0.85) : Theme.quiet)
        }
        .foregroundColor(selected ? .white : Theme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(RowBox(selected: selected))
        .contentShape(Rectangle())
    }
}

/// flat until picked, then it's a pink box that lifts off the page
struct RowBox: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if selected {
            content.boxy(Theme.pink, line: Theme.pinkDark, lifted: true)
        } else {
            content
        }
    }
}

struct ClipPreview: View {
    let clip: Clip?

    var body: some View {
        if let clip {
            VStack(alignment: .leading, spacing: 0) {
                content(clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
                Rule()
                info(clip).padding(14)
            }
        } else {
            Text("(\\_/)\n( •.•)\n/ >📋")
                .font(Theme.font(18))
                .foregroundColor(Theme.pink)
        }
    }

    @ViewBuilder
    private func content(_ clip: Clip) -> some View {
        switch clip.kind {
        case .image:
            VStack(alignment: .leading, spacing: 10) {
                if let path = clip.image, let image = Thumbs.get(path, size: 900) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                }
                if !clip.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(clip.tags, id: \.self) { Chip(text: $0, fill: Theme.mint) }
                        }
                        .padding(2)
                    }
                }
                ScrollView {
                    Text(clip.vision ?? "👀 looking…")
                        .font(Theme.font(12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .color:
            VStack(alignment: .leading, spacing: 10) {
                (clip.swatch ?? Theme.page)
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .boxy(clip.swatch ?? Theme.page)
                Text(clip.body).font(Theme.font(20)).textSelection(.enabled)
            }
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                Text("🔗 " + (URL(string: clip.body.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "link"))
                    .font(Theme.font(16, .bold))
                    .foregroundColor(Theme.pink)
                Text(clip.body).font(Theme.font(12)).textSelection(.enabled)
            }
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(clip.body.split(separator: "\n").map(String.init), id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: path).lastPathComponent).font(Theme.font(13, .bold))
                            Text(path).font(Theme.font(11)).foregroundColor(Theme.quiet).lineLimit(1)
                        }
                    }
                }
            }
        case .text:
            ScrollView {
                Text(String(clip.body.prefix(20_000)))
                    .font(Theme.font(12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func info(_ clip: Clip) -> some View {
        var rows: [(String, String)] = []
        if !clip.app.isEmpty { rows.append(("from", clip.app)) }
        rows.append(("kind", clip.kind.label))
        switch clip.kind {
        case .text, .link, .color:
            let words = clip.body.split(whereSeparator: { $0.isWhitespace }).count
            rows.append(("size", "\(clip.body.count) chars · \(words) words"))
        case .image:
            if let path = clip.image, let px = Thumbs.pixels(path) { rows.append(("size", "\(px.0)×\(px.1)")) }
        case .file:
            break
        }
        rows.append(("used", clip.count == 1 ? "once" : "\(clip.count) times"))
        rows.append(("first", Ago.say(clip.created)))
        rows.append(("last", Ago.say(clip.used)))

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline) {
                    Text(rows[i].0).foregroundColor(Theme.quiet).frame(width: 52, alignment: .leading)
                    Text(rows[i].1).lineLimit(1)
                    Spacer()
                }
                .font(Theme.font(11))
            }
        }
    }
}

struct EmojiView: View {
    @ObservedObject var model: EmojiModel
    private let grid = Array(repeating: GridItem(.fixed(50), spacing: 8), count: EmojiModel.columns)

    var body: some View {
        Overlay(
            placeholder: "search emoji…",
            query: $model.query,
            filters: EmojiFilter.allCases.map(\.rawValue),
            filter: model.filter.rawValue,
            pickFilter: { model.filter = EmojiFilter(rawValue: $0) ?? .all },
            status: model.current.map { "\($0.char)  \($0.name)" } ?? "\(model.results.count) emoji",
            keys: [
                Keycap(key: "↩", label: "type"),
                Keycap(key: "⌘↩", label: "copy"),
                Keycap(key: "⇥", label: "filter"),
            ]
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    if model.results.isEmpty {
                        Text("🐇  no emoji for that")
                            .font(Theme.font(13))
                            .foregroundColor(Theme.pink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    LazyVGrid(columns: grid, spacing: 8) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, emoji in
                            let on = index == model.selected
                            Text(emoji.char)
                                .font(.system(size: 28))
                                .frame(width: 50, height: 50)
                                .modifier(EmojiBox(on: on))
                                .contentShape(Rectangle())
                                .fadeIn(index)
                                .onTapGesture { model.onPick?(emoji, true) }
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 14))
                }
                .onChange(of: model.selected) { index in
                    if model.results.indices.contains(index) { proxy.scrollTo(model.results[index].id) }
                }
            }
        }
    }
}

struct EmojiBox: ViewModifier {
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.boxy(Theme.pink, line: Theme.pinkDark, lifted: true)
        } else {
            content
        }
    }
}
