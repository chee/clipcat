import Foundation

struct Emoji: Identifiable, Equatable {
    let char: String
    let name: String
    let words: [String]
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

    /// built from the unicode tables at launch, so it's as new as the os.
    static func load() -> [Emoji] {
        var out: [Emoji] = []
        var seen = Set<String>()

        func add(_ char: String, _ name: String) {
            guard !seen.contains(char) else { return }
            seen.insert(char)
            let extra = aliases[char] ?? ""
            let words = (name + " " + extra).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            out.append(Emoji(char: char, name: name.lowercased(), words: words))
        }

        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let p = scalar.properties
                guard p.isEmoji, !p.isEmojiModifier, !(0x1F1E6...0x1F1FF).contains(value),
                      let name = p.name
                else { continue }
                add(p.isEmojiPresentation ? String(scalar) : String(scalar) + "\u{FE0F}", name)
            }
        }

        for (char, words) in aliases where char.unicodeScalars.count > 2 {
            add(char, words)
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
            add(flag, "flag " + country + " " + code)
        }
        return out
    }
}
