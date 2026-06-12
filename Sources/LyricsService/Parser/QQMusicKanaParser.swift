import Foundation
import LyricsCore

extension Lyrics.IDTagKey {
    static let qqMusicKana = Lyrics.IDTagKey("kana")
}

extension Lyrics {
    public func applyQQMusicKanaFurigana() {
        guard let kana = idTags[.qqMusicKana] else { return }

        var parser = QQMusicKanaParser(kana)
        var hasFurigana = false
        for index in lines.indices {
            let attributes = parser.attributes(for: lines[index].content)
            guard !attributes.isEmpty else { continue }
            lines[index].attachments.furigana = .init(attributes: attributes)
            hasFurigana = true
        }

        if hasFurigana {
            metadata.attachmentTags.insert(.furigana)
        }
    }
}

private struct QQMusicKanaParser {
    private struct Segment {
        let characterCount: Int
        let reading: String
    }

    private let segments: [Segment]
    private var segmentIndex = 0

    init(_ kana: String) {
        self.segments = Self.parseSegments(from: kana)
    }

    mutating func attributes(for content: String) -> [LyricsLine.Attachments.RangeAttribute.Attribute] {
        var attributes: [LyricsLine.Attachments.RangeAttribute.Attribute] = []
        var scanIndex = content.startIndex

        while segmentIndex < segments.count {
            guard let startIndex = nextKanaBaseIndex(in: content, from: scanIndex) else {
                break
            }

            let segment = segments[segmentIndex]
            guard let (range, nextIndex) = rangeForKanaBaseCount(
                segment.characterCount,
                in: content,
                from: startIndex
            ) else {
                break
            }

            if !segment.reading.isEmpty {
                let lowerBound = content.distance(from: content.startIndex, to: range.lowerBound)
                let upperBound = content.distance(from: content.startIndex, to: range.upperBound)
                attributes.append(.init(range: lowerBound ..< upperBound, content: segment.reading))
            }
            segmentIndex += 1
            scanIndex = nextIndex
        }

        return attributes
    }

    // Stream grammar (verified against live QQMusic data): a unit is a single
    // count digit followed by an optional reading. An empty reading still
    // consumes `count` base units without annotating them (unannotated digit
    // runs like リッケン620, translated-title characters, etc.).
    private static func parseSegments(from kana: String) -> [Segment] {
        let normalized = kana.replacingOccurrences(
            of: #"\(\d+,\d+\)"#,
            with: "",
            options: .regularExpression
        )
        var segments: [Segment] = []
        var pendingCount: Int?
        var reading = ""
        for character in normalized {
            if character.isASCII, let digit = character.wholeNumberValue {
                if let count = pendingCount, count > 0 {
                    segments.append(Segment(characterCount: count, reading: reading))
                }
                pendingCount = digit
                reading = ""
            } else {
                reading.append(character)
            }
        }
        if let count = pendingCount, count > 0 {
            segments.append(Segment(characterCount: count, reading: reading))
        }
        return segments
    }

    private func nextKanaBaseIndex(in content: String, from index: String.Index) -> String.Index? {
        var current = index
        while current < content.endIndex {
            if content[current].isQQMusicKanaBase || content[current].isQQMusicKanaDigit {
                return current
            }
            current = content.index(after: current)
        }
        return nil
    }

    private func rangeForKanaBaseCount(
        _ count: Int,
        in content: String,
        from index: String.Index
    ) -> (Range<String.Index>, String.Index)? {
        var current = index
        var lowerBound: String.Index?
        var upperBound: String.Index?
        var remaining = count

        while current < content.endIndex, remaining > 0 {
            if content[current].isQQMusicKanaDigit {
                // QQMusic counts a contiguous digit run (e.g. １１５ or 366)
                // as a single annotated unit with one reading.
                var runEnd = content.index(after: current)
                while runEnd < content.endIndex, content[runEnd].isQQMusicKanaDigit {
                    runEnd = content.index(after: runEnd)
                }
                lowerBound = lowerBound ?? current
                upperBound = runEnd
                remaining -= 1
                current = runEnd
            } else {
                let next = content.index(after: current)
                if content[current].isQQMusicKanaBase {
                    lowerBound = lowerBound ?? current
                    upperBound = next
                    remaining -= 1
                }
                current = next
            }
        }

        guard remaining == 0, let lowerBound, let upperBound else {
            return nil
        }
        return (lowerBound ..< upperBound, current)
    }
}

private extension Character {
    var isQQMusicKanaBase: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400 ... 0x9FFF,
                 0xF900 ... 0xFAFF:
                return true
            default:
                return scalar == "々" || scalar == "〆" || scalar == "ヶ"
            }
        }
    }

    var isQQMusicKanaDigit: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x30 ... 0x39, // 0-9
                 0xFF10 ... 0xFF19: // ０-９
                return true
            default:
                return false
            }
        }
    }
}
