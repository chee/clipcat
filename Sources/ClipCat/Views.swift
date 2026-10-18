import SwiftUI

extension Clip.Kind {
    var label: String {
        switch self {
        case .text: return "TEXT"
        case .image: return "PIC"
        case .file: return "FILE"
        }
    }

    var color: Color {
        switch self {
        case .text: return Theme.pink
        case .image: return Theme.sky
        case .file: return Theme.mint
        }
    }
}

extension Clip {
    var title: String {
        switch kind {
        case .text:
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
}

struct ClipsView: View {
    @ObservedObject var model: ClipModel

    var body: some View {
        Shell(
            title: "\(Theme.bunny) clipcat",
            color: Theme.pink,
            query: $model.query,
            placeholder: "search clips, even words in pictures…",
            footer: "↩ paste · ⌘↩ copy · ⌘1–9 quick paste · ⌘⌫ forget · esc"
        ) {
            HStack(spacing: 0) {
                list.frame(width: 380)
                Rule(vertical: true)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if model.clips.isEmpty {
                        Text(model.query.isEmpty ? "nothing yet. copy something!" : "no clips match")
                            .font(Theme.font(13))
                            .padding(.top, 40)
                    }
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(clip: clip, index: index, selected: index == model.selected)
                            .onTapGesture(count: 2) { model.onPick?(clip, true) }
                            .onTapGesture { model.selected = index }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12))
            }
            .onChange(of: model.selected) { index in
                if model.clips.indices.contains(index) { proxy.scrollTo(model.clips[index].id) }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let clip = model.current {
            VStack(alignment: .leading, spacing: 8) {
                if let path = clip.image, let image = Thumbs.get(path, size: 720) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .padding(6)
                        .boxy(Theme.card, shadow: 4)
                }
                if !clip.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(clip.tags, id: \.self) { Chip(text: $0, color: Theme.lilac) }
                        }
                    }
                }
                ScrollView {
                    Text(String((clip.kind == .image ? clip.vision ?? "" : clip.body).prefix(20_000)))
                        .font(Theme.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("\(clip.body.count) chars · first copied \(Ago.say(clip.created))")
                    .font(Theme.font(10, .semibold))
                    .opacity(0.6)
            }
            .padding(12)
        } else {
            Text("(\\_/)\n( •.•)\n/ >📋")
                .font(Theme.font(18))
                .multilineTextAlignment(.leading)
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let path = clip.image, let image = Thumbs.get(path, size: 120) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipped()
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Chip(text: clip.kind.label, color: clip.kind.color)
                    if index < 9 { Chip(text: "⌘\(index + 1)", color: Theme.card) }
                    Spacer()
                    Text(Ago.say(clip.used)).font(Theme.font(10, .semibold)).opacity(0.6)
                }
                Text(clip.title)
                    .font(Theme.font(13, .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .boxy(selected ? Theme.lemon : Theme.card, shadow: selected ? 4 : 0)
        .contentShape(Rectangle())
    }
}

struct EmojiView: View {
    @ObservedObject var model: EmojiModel
    private let grid = Array(repeating: GridItem(.fixed(44), spacing: 6), count: EmojiModel.columns)

    var body: some View {
        Shell(
            title: "\(Theme.bunny) emoji",
            color: Theme.sky,
            query: $model.query,
            placeholder: "search emoji…",
            footer: model.current.map { "\($0.char)  \($0.name)  ·  ↩ type · ⌘↩ copy" } ?? "↩ type · ⌘↩ copy · esc"
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 6) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, emoji in
                            let on = index == model.selected
                            Text(emoji.char)
                                .font(.system(size: 26))
                                .frame(width: 44, height: 44)
                                .boxy(on ? Theme.lemon : Theme.card, shadow: on ? 3 : 0)
                                .contentShape(Rectangle())
                                .onTapGesture { model.onPick?(emoji, true) }
                        }
                    }
                    .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 14))
                }
                .onChange(of: model.selected) { index in
                    if model.results.indices.contains(index) { proxy.scrollTo(model.results[index].id) }
                }
            }
        }
    }
}
