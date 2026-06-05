import Foundation
import LyricsCore

extension Lyrics.IDTagKey {
    static let qqMusicKana = Lyrics.IDTagKey("kana")
}

extension Lyrics {
    func applyQQMusicKanaFurigana() {
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

            let lowerBound = content.distance(from: content.startIndex, to: range.lowerBound)
            let upperBound = content.distance(from: content.startIndex, to: range.upperBound)
            attributes.append(.init(range: lowerBound ..< upperBound, content: segment.reading))
            segmentIndex += 1
            scanIndex = nextIndex
        }

        return attributes
    }

    private static func parseSegments(from kana: String) -> [Segment] {
        let normalized = kana.replacingOccurrences(
            of: #"\(\d+,\d+\)"#,
            with: "",
            options: .regularExpression
        )
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)([^\d]+)"#) else {
            return []
        }
        let nsString = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            guard match.numberOfRanges == 3,
                  let count = Int(nsString.substring(with: match.range(at: 1))),
                  count > 0 else {
                return nil
            }
            let reading = nsString.substring(with: match.range(at: 2))
            guard !reading.isEmpty else { return nil }
            return Segment(characterCount: count, reading: reading)
        }
    }

    private func nextKanaBaseIndex(in content: String, from index: String.Index) -> String.Index? {
        var current = index
        while current < content.endIndex {
            if content[current].isQQMusicKanaBase {
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
            let next = content.index(after: current)
            if content[current].isQQMusicKanaBase {
                lowerBound = lowerBound ?? current
                upperBound = next
                remaining -= 1
            }
            current = next
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
}
