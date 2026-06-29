import Foundation
import LyricsCore

// MARK: - TTML Initializer

extension Lyrics {
    /// Initialize from Apple Music TTML (Timed Text Markup Language) format.
    ///
    /// Parses `<p>` as `LyricsLine`, `<span>` as `InlineTimeTag` (word-level
    /// karaoke), and `<iTunesMetadata>/<translations>` as per-line translation
    /// attachments (`tr:{lang}`).
    ///
    /// Time formats: `SS.mmm`, `M:SS.mmm`, `MM:SS.mmm`
    public convenience init?(ttmlContent xmlString: String) {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        let parser = TTMLParser()
        guard parser.parse(data: data), !parser.lines.isEmpty else {
            return nil
        }

        var idTags: [IDTagKey: String] = [:]
        if let lang = parser.lang {
            idTags[.init("lang")] = lang
        }
        if let author = parser.author {
            idTags[.artist] = author
        }

        // Populate attachmentTags so that Lyrics.metadata.translationLanguages
        // reports the correct language codes (e.g. ["zh-Hans"]). Without this,
        // consumers like KaraokeLyricsController would look up a bare Tag("tr")
        // and miss the lang-qualified Tag("tr:zh-Hans") stored on each line.
        if !parser.translations.isEmpty {
            var tags = parser.metadata.attachmentTags
            for lang in parser.translations.keys {
                tags.insert(.translation(languageCode: lang))
            }
            parser.metadata.attachmentTags = tags
        }

        self.init(lines: parser.lines, idTags: idTags, metadata: parser.metadata)
    }
}

// MARK: - TTML XML Parser

private final class TTMLParser: NSObject, XMLParserDelegate {

    // --- Output ---
    var lines: [LyricsLine] = []
    var metadata: Lyrics.Metadata = .init()
    var lang: String?
    var author: String?

    // --- Line state ---
    private var lineBegin: TimeInterval = 0
    private var lineEnd: TimeInterval = 0
    private var lineItunesKey: String?
    private var lineText = ""
    private var timetagTags: [LyricsLine.Attachments.InlineTimeTag.Tag] = []

    // --- Translation state (lang → key → text) ---
    var translations: [String: [String: String]] = [:]

    // --- Head metadata tracking ---
    // depth > 0 → we're inside <iTunesMetadata>; route all elements
    // through handleMetaStart / handleMetaEnd.
    private var depthInMeta = 0

    // Active <translation> language while parsing its children.
    private var currentTranslationLang: String?
    // Active <text for="..."> key while accumulating text.
    private var currentTextFor: String?
    // Collected songwriters.
    private var songwriters: [String] = []

    // MARK: - Entry

    func parse(data: Data) -> Bool {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        return xmlParser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if depthInMeta > 0 {
            handleMetaStart(elementName, attributes: attributeDict)
            return
        }

        switch elementName {
        case "tt":
            lang = attributeDict["xml:lang"]
        case "p":
            beginLine(attributes: attributeDict)
        case "span":
            beginSpan(attributes: attributeDict)
        case "iTunesMetadata":
            depthInMeta = 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // In metadata, text inside <text> / <songwriter> needs to go to
        // lineText (reused as a scratch buffer).
        if depthInMeta > 0 {
            lineText += string
        } else {
            // Body: text inside <p> (and between <span>s).
            lineText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if depthInMeta > 0 {
            handleMetaEnd(elementName)
            return
        }

        switch elementName {
        case "p":
            endLine()
        default:
            break
        }
    }

    // MARK: - Metadata element handling

    private func handleMetaStart(_ elementName: String, attributes: [String: String]) {
        depthInMeta += 1
        switch elementName {
        case "translation":
            currentTranslationLang = attributes["xml:lang"] ?? attributes["lang"]
        case "text":
            currentTextFor = attributes["for"]
            lineText = ""
        case "songwriter":
            lineText = ""
        default:
            break
        }
    }

    private func handleMetaEnd(_ elementName: String) {
        depthInMeta -= 1
        switch elementName {
        case "text":
            if let key = currentTextFor, let lang = currentTranslationLang {
                let text = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    translations[lang, default: [:]][key] = text
                }
            }
            currentTextFor = nil
            lineText = ""
        case "translation":
            currentTranslationLang = nil
        case "songwriter":
            let writer = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !writer.isEmpty {
                songwriters.append(writer)
            }
            lineText = ""
        case "iTunesMetadata":
            if !songwriters.isEmpty {
                author = songwriters.joined(separator: ", ")
            }
            // depthInMeta is now 0 — back to body parsing.
        default:
            break
        }
    }

    // MARK: - <p>

    private func beginLine(attributes: [String: String]) {
        lineBegin = TTMLParser.parseTime(attributes["begin"])
        lineEnd = TTMLParser.parseTime(attributes["end"])
        // XMLParser may or may not preserve namespace prefixes in attributeDict.
        // Try both qualified and bare forms.
        lineItunesKey = attributes["itunes:key"] ?? attributes["key"]
        lineText = ""
        timetagTags = []
    }

    private func endLine() {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Leading whitespace inside <p> (e.g. XML indentation before the first
        // <span>) shifts all tag indices. Subtract it so they match the trimmed
        // content string that the renderer uses.
        let leadingOffset = lineText.prefix(while: { $0.isWhitespace || $0.isNewline }).count

        let duration = max(0, lineEnd - lineBegin)

        var attachDict: [LyricsLine.Attachments.Tag: LyricsLineAttachment] = [:]

        if !timetagTags.isEmpty {
            var pruned = timetagTags.map {
                LyricsLine.Attachments.InlineTimeTag.Tag(
                    index: max(0, $0.index - leadingOffset),
                    time: $0.time
                )
            }
            while let last = pruned.last, last.index >= trimmed.count {
                pruned.removeLast()
            }
            attachDict[.timetag] = LyricsLine.Attachments.InlineTimeTag(
                tags: pruned,
                duration: duration
            )
        }

        // Attach translations keyed by itunes:key="L{N}"
        if let key = lineItunesKey {
            for (lang, langTrans) in translations {
                if let text = langTrans[key] {
                    let tag = LyricsLine.Attachments.Tag.translation(languageCode: lang)
                    attachDict[tag] = LyricsLine.Attachments.PlainText(text)
                }
            }
        }

        let attachments = LyricsLine.Attachments(attachments: attachDict)
        let line = LyricsLine(content: trimmed, position: lineBegin, attachments: attachments)
        lines.append(line)
    }

    // MARK: - <span>

    private func beginSpan(attributes: [String: String]) {
        let begin = TTMLParser.parseTime(attributes["begin"])
        let offset = max(0, begin - lineBegin)
        timetagTags.append(.init(index: lineText.count, time: offset))
    }
}

// MARK: - Time Parsing

extension TTMLParser {
    /// Parse Apple Music TTML time strings.
    ///
    /// Supported formats:
    /// - `SS.mmm` → seconds only
    /// - `M:SS.mmm` / `MM:SS.mmm` → minutes + seconds
    static func parseTime(_ string: String?) -> TimeInterval {
        guard let string, !string.isEmpty else { return 0 }
        let parts = string.split(separator: ":")
        switch parts.count {
        case 1:
            return TimeInterval(string) ?? 0
        case 2:
            let minutes = TimeInterval(parts[0]) ?? 0
            let seconds = TimeInterval(parts[1]) ?? 0
            return minutes * 60 + seconds
        default:
            return 0
        }
    }
}
