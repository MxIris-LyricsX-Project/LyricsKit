import Foundation
import LyricsCore

// MARK: - TTML Initializer

extension Lyrics {
    /// Initialize from Apple Music TTML (Timed Text Markup Language) format.
    ///
    /// Parses `<p>` as `LyricsLine`, preserves `<span>` word endings and nested
    /// syllables as `SynchronizedTextTiming`, maintains `InlineTimeTag` as the
    /// compatibility representation, and imports `<iTunesMetadata>/<translations>`
    /// as per-line translation attachments (`tr:{lang}`).
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
    private var synchronizedWords: [LyricsLine.Attachments.SynchronizedTextTiming.Word] = []
    private var openSpans: [OpenSpan] = []
    private var isInsideLine = false

    private struct OpenSpan {
        let startingCharacterIndex: Int
        let startingTime: TimeInterval?
        let endingTime: TimeInterval?
        var nestedSyllables: [LyricsLine.Attachments.SynchronizedTextTiming.Syllable] = []
    }

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
        } else if isInsideLine {
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
        case "span":
            endSpan()
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
        synchronizedWords = []
        openSpans = []
        isInsideLine = true
    }

    private func endLine() {
        defer {
            openSpans = []
            isInsideLine = false
        }
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

        let adjustedSynchronizedWords = synchronizedWords.compactMap { word -> LyricsLine.Attachments.SynchronizedTextTiming.Word? in
            guard let adjustedWordRange = adjustedCharacterRange(
                word.characterRange,
                leadingOffset: leadingOffset,
                characterCount: trimmed.count
            ) else {
                return nil
            }
            let adjustedSyllables = word.syllables.compactMap { syllable -> LyricsLine.Attachments.SynchronizedTextTiming.Syllable? in
                guard let adjustedSyllableRange = adjustedCharacterRange(
                    syllable.characterRange,
                    leadingOffset: leadingOffset,
                    characterCount: trimmed.count
                ),
                    adjustedWordRange.contains(adjustedSyllableRange.lowerBound),
                    adjustedSyllableRange.upperBound <= adjustedWordRange.upperBound
                else {
                    return nil
                }
                return LyricsLine.Attachments.SynchronizedTextTiming.Syllable(
                    characterRange: adjustedSyllableRange,
                    timeRange: syllable.timeRange
                )
            }
            return LyricsLine.Attachments.SynchronizedTextTiming.Word(
                characterRange: adjustedWordRange,
                timeRange: word.timeRange,
                syllables: adjustedSyllables
            )
        }
        if !adjustedSynchronizedWords.isEmpty {
            let synchronizedTextTiming = LyricsLine.Attachments.SynchronizedTextTiming(
                words: adjustedSynchronizedWords,
                duration: duration
            )
            if synchronizedTextTiming.isValid(forCharacterCount: trimmed.count) {
                attachDict[.synchronizedTextTiming] = synchronizedTextTiming
            }
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
        guard isInsideLine else { return }
        openSpans.append(OpenSpan(
            startingCharacterIndex: lineText.count,
            startingTime: TTMLParser.parseOptionalTime(attributes["begin"]).map { max(0, $0 - lineBegin) },
            endingTime: TTMLParser.parseOptionalTime(attributes["end"]).map { max(0, $0 - lineBegin) }
        ))
    }

    private func endSpan() {
        guard isInsideLine, let completedSpan = openSpans.popLast() else { return }
        let characterRange = completedSpan.startingCharacterIndex ..< lineText.count
        guard !characterRange.isEmpty else { return }

        let startingTime = completedSpan.startingTime ?? completedSpan.nestedSyllables.first?.timeRange.lowerBound
        let endingTime = completedSpan.endingTime ?? completedSpan.nestedSyllables.last?.timeRange.upperBound
        let completedTimeRange = startingTime.flatMap { resolvedStartingTime in
            endingTime.map { resolvedEndingTime in
                resolvedStartingTime ..< max(resolvedStartingTime, resolvedEndingTime)
            }
        }

        if var parentSpan = openSpans.popLast() {
            if completedSpan.nestedSyllables.isEmpty, let completedTimeRange {
                parentSpan.nestedSyllables.append(.init(
                    characterRange: characterRange,
                    timeRange: completedTimeRange
                ))
            } else {
                parentSpan.nestedSyllables.append(contentsOf: completedSpan.nestedSyllables)
            }
            openSpans.append(parentSpan)
            return
        }

        if let startingTime {
            timetagTags.append(.init(index: characterRange.lowerBound, time: startingTime))
        }
        guard let completedTimeRange else { return }
        let syllables = completedSpan.nestedSyllables.isEmpty
            ? [LyricsLine.Attachments.SynchronizedTextTiming.Syllable(
                characterRange: characterRange,
                timeRange: completedTimeRange
            )]
            : completedSpan.nestedSyllables
        synchronizedWords.append(.init(
            characterRange: characterRange,
            timeRange: completedTimeRange,
            syllables: syllables
        ))
    }

    private func adjustedCharacterRange(
        _ characterRange: Range<Int>,
        leadingOffset: Int,
        characterCount: Int
    ) -> Range<Int>? {
        let lowerBound = min(characterCount, max(0, characterRange.lowerBound - leadingOffset))
        let upperBound = min(characterCount, max(lowerBound, characterRange.upperBound - leadingOffset))
        guard lowerBound < upperBound else { return nil }
        return lowerBound ..< upperBound
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
        parseOptionalTime(string) ?? 0
    }

    static func parseOptionalTime(_ string: String?) -> TimeInterval? {
        guard let string, !string.isEmpty else { return nil }
        let parts = string.split(separator: ":")
        switch parts.count {
        case 1:
            guard let time = TimeInterval(string), time.isFinite else { return nil }
            return time
        case 2:
            guard let minutes = TimeInterval(parts[0]),
                  let seconds = TimeInterval(parts[1]),
                  minutes.isFinite,
                  seconds.isFinite
            else {
                return nil
            }
            let time = minutes * 60 + seconds
            return time.isFinite ? time : nil
        default:
            return nil
        }
    }
}
