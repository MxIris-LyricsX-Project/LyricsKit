import Foundation
import LyricsCore
import FoundationToolbox

enum QQMusicXMLDecoder {
    static func decodeLyricContents(from document: XMLDocument) -> [String: String] {
        let mappings: [(xpath: String, key: String)] = [
            ("//content", "orig"),
            ("//contentts", "ts"),
        ]
        var result: [String: String] = [:]
        for mapping in mappings {
            guard let node = (try? document.nodes(forXPath: mapping.xpath))?.first,
                  let text = node.stringValue,
                  let decoded = decodeSingleLyricText(text) else {
                continue
            }
            result[mapping.key] = decoded
        }
        return result
    }

    static func decodeSingleLyricText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let compact = trimmed.replacingOccurrences(
            of: "\\s+",
            with: "",
            options: .regularExpression
        )

        let decoded: String
        if isStrictHex(compact) {
            guard let decryptText = decryptQQMusicQrc(compact) else { return nil }
            decoded = decryptText
        } else {
            decoded = trimmed
        }

        guard decoded.contains("<?xml") else {
            return decoded
        }

        if let nestedDoc = try? XMLUtils.create(content: decoded),
           let lyricNode = (try? nestedDoc.nodes(forXPath: "//*[@LyricContent]"))?.first as? XMLElement,
           let content = lyricNode.attribute(forName: "LyricContent")?.stringValue,
           !content.isEmpty {
            let formatted = lyricFormat(content)
            return normalizeQQQrcContent(formatted)
        }

        if let content = extractLyricContentAttribute(from: decoded), !content.isEmpty {
            let formatted = lyricFormat(content)
            return normalizeQQQrcContent(formatted)
        }

        return decoded
    }

    static func normalizeQQQrcContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"\s+(?=\[\d+,\d+\])"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\]\s+\["#, with: "]\n[", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the value of the `LyricContent` attribute from a raw XML string
    /// without going through an XML parser (which would collapse newlines to spaces).
    static func extractLyricContentAttribute(from xmlString: String) -> String? {
        let marker = "LyricContent=\""
        guard let markerRange = xmlString.range(of: marker) else { return nil }
        let afterMarker = xmlString[markerRange.upperBound...]

        var escaped = false
        var endQuote: String.Index?
        for idx in afterMarker.indices {
            let character = afterMarker[idx]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                endQuote = idx
                break
            }
        }

        guard let endQuote else { return nil }
        let content = String(afterMarker[..<endQuote])
        return content.isEmpty ? nil : content
    }

    static func isStrictHex(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, candidate.count % 2 == 0 else { return false }
        // `Character.isHexDigit` accepts only ASCII [0-9A-Fa-f], unlike `isNumber`
        // which also matches non-ASCII digits (e.g. fullwidth `１`).
        return candidate.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Some QQ fallback lyrics use `[HH:MM:SS(.xx)]` timestamps, while the Lyrics parser
    /// accepts `[MM:SS(.xx)]`. Convert hours into minutes for compatibility.
    static func normalizeExtendedLrcTimestamps(_ content: String) -> String {
        let pattern = #"\[(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        guard !matches.isEmpty else { return content }

        var normalized = content
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }
            let hoursString = nsContent.substring(with: match.range(at: 1))
            let minutesString = nsContent.substring(with: match.range(at: 2))
            let secondsString = nsContent.substring(with: match.range(at: 3))
            guard let hours = Int(hoursString), let minutes = Int(minutesString) else { continue }
            let mergedMinutes = hours * 60 + minutes
            let replacement = "[\(mergedMinutes):\(secondsString)]"
            if let range = Range(match.range, in: normalized) {
                normalized.replaceSubrange(range, with: replacement)
            }
        }
        return normalized
    }
}
