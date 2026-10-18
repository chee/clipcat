import Foundation

struct Emoji: Identifiable, Equatable {
    enum Group: String, CaseIterable { case faces, people, nature, food, things, flags }

    let char: String
    let name: String
    let words: [String]
    let group: Group
    var id: String { char }
}

extension Emoji {
    /// friendlier words for some favourites whose unicode names are a bit much
    private static let aliases: [String: String] = [
        "❤️": "red heart love",
        "😂": "lol laugh crying",
        "🤣": "lol rofl laugh",
        "👍": "thumbs up yes ok",
        "👎": "thumbs down no",
        "🔥": "lit hot",
        "✨": "sparkle shiny magic",
        "🥺": "pleading puppy eyes",
        "😭": "sob cry",
        "💀": "dead skull lol",
        "🙏": "please thanks pray",
        "👀": "eyes look",
        "🐰": "bunny rabbit",
        "🐇": "bunny rabbit",
        "🐱": "cat kitty",
        "🎉": "party tada yay",
        "✅": "check done yes",
        "❌": "x no cross",
        "💖": "heart sparkle love",
        "🏳️‍⚧️": "trans flag transgender pride",
        "🏳️‍🌈": "rainbow flag pride gay",
    ]

    private static let ranges: [ClosedRange<UInt32>] = [
        0x1F600...0x1F64F, // faces
        0x1F900...0x1F9FF,
        0x1FA70...0x1FAFF,
        0x1F300...0x1F5FF,
        0x1F680...0x1F6FF,
        0x1F7E0...0x1F7FF,
        0x2600...0x27BF,
        0x2300...0x23FF,
        0x2B00...0x2BFF,
        0x1F000...0x1F2FF,
    ]

    /// rough groups by code point block. the specific ranges go first.
    private static let groups: [(ClosedRange<UInt32>, Group)] = [
        (0x1F918...0x1F91F, .people),
        (0x1F926...0x1F937, .people),
        (0x1F9B0...0x1F9B9, .people),
        (0x1F9CD...0x1F9DF, .people),
        (0x1F440...0x1F450, .people),
        (0x1F466...0x1F487, .people),
        (0x1F645...0x1F64F, .people),
        (0x1FAF0...0x1FAFF, .people),
        (0x270A...0x270D, .people),
        (0x261D...0x261D, .people),
        (0x1F600...0x1F644, .faces),
        (0x1F910...0x1F92F, .faces),
        (0x1F970...0x1F97F, .faces),
        (0x1F9D0...0x1F9D0, .faces),
        (0x1FAE0...0x1FAEF, .faces),
        (0x263A...0x263A, .faces),
        (0x2639...0x2639, .faces),
        (0x1F345...0x1F37F, .food),
        (0x1F950...0x1F96F, .food),
        (0x1F9C0...0x1F9CB, .food),
        (0x1FAD0...0x1FADF, .food),
        (0x1F300...0x1F344, .nature),
        (0x1F400...0x1F43F, .nature),
        (0x1F980...0x1F9AE, .nature),
        (0x1FAB0...0x1FABF, .nature),
        (0x2600...0x2604, .nature),
        (0x26C4...0x26C8, .nature),
        (0x2744...0x2744, .nature),
    ]

    private static func group(of value: UInt32) -> Group {
        groups.first { $0.0.contains(value) }?.1 ?? .things
    }

    /// built from the unicode tables at launch, so it's as new as the os.
    static func load() -> [Emoji] {
        var out: [Emoji] = []
        var seen = Set<String>()

        func add(_ char: String, _ name: String, _ group: Group) {
            guard !seen.contains(char) else { return }
            seen.insert(char)
            let extra = aliases[char] ?? ""
            let words = (name + " " + extra).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            out.append(Emoji(char: char, name: name.lowercased(), words: words, group: group))
        }

        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let p = scalar.properties
                guard p.isEmoji, !p.isEmojiModifier, !(0x1F1E6...0x1F1FF).contains(value),
                      let name = p.name
                else { continue }
                add(p.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}", name, Self.group(of: value))
            }
        }

        for (char, words) in aliases where char.unicodeScalars.count > 2 {
            add(char, words, .flags)
        }

        let english = Locale(identifier: "en_US")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }),
                  let country = english.localizedString(forRegionCode: code)
            else { continue }
            var flag = ""
            for letter in code.unicodeScalars {
                if let indicator = Unicode.Scalar(0x1F1E6 + letter.value - 65) { flag.unicodeScalars.append(indicator) }
            }
            add(flag, "flag " + country + " " + code, .flags)
        }
        return out
    }
}
