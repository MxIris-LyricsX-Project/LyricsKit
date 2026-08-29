import Foundation
import LyricsCore
import Testing
@testable import LyricsService

struct TimedTextMarkupLanguageParserTests {
    @Test func flatSpansPreserveWordStartAndEndTimes() throws {
        let timedTextMarkupLanguageContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="zh-Hant">
          <body><div><p begin="29.188" end="32.398"><span begin="29.188" end="30.449">故事的</span><span begin="30.449" end="32.398">小黃花</span></p></div></body>
        </tt>
        """

        let lyrics = try #require(Lyrics(ttmlContent: timedTextMarkupLanguageContent))
        let line = try #require(lyrics.lines.first)
        let timing = try #require(line.attachments.synchronizedTextTiming)

        #expect(line.content == "故事的小黃花")
        #expect(abs((timing.duration ?? 0) - 3.21) < 0.000_001)
        #expect(timing.words.count == 2)
        #expect(timing.words[0].characterRange == 0 ..< 3)
        #expect(abs(timing.words[0].timeRange.lowerBound - 0) < 0.000_001)
        #expect(abs(timing.words[0].timeRange.upperBound - 1.261) < 0.000_001)
        #expect(timing.words[0].syllables.count == 1)
        #expect(timing.words[0].syllables[0].characterRange == 0 ..< 3)
        #expect(abs(timing.words[0].syllables[0].timeRange.upperBound - 1.261) < 0.000_001)
        #expect(timing.words[1].characterRange == 3 ..< 6)
        #expect(abs(timing.words[1].timeRange.lowerBound - 1.261) < 0.000_001)
        #expect(abs(timing.words[1].timeRange.upperBound - 3.21) < 0.000_001)

        let compatibilityTiming = try #require(line.attachments.timetag)
        #expect(compatibilityTiming.tags.map(\.index) == [0, 3])
        #expect(abs(compatibilityTiming.tags[1].time - 1.261) < 0.000_001)
    }

    @Test func nestedSpansBecomeSyllablesWithinOneWord() throws {
        let timedTextMarkupLanguageContent = """
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en">
          <body><div><p begin="20.000" end="22.000"><span begin="20.000" end="22.000"><span begin="20.000" end="20.500">Hel</span><span begin="20.500" end="22.000">lo</span></span></p></div></body>
        </tt>
        """

        let lyrics = try #require(Lyrics(ttmlContent: timedTextMarkupLanguageContent))
        let timing = try #require(lyrics.lines.first?.attachments.synchronizedTextTiming)
        let word = try #require(timing.words.first)

        #expect(timing.words.count == 1)
        #expect(word.characterRange == 0 ..< 5)
        #expect(word.timeRange == 0 ..< 2)
        #expect(word.syllables.count == 2)
        #expect(word.syllables[0].characterRange == 0 ..< 3)
        #expect(word.syllables[0].timeRange == 0 ..< 0.5)
        #expect(word.syllables[1].characterRange == 3 ..< 5)
        #expect(word.syllables[1].timeRange == 0.5 ..< 2)
    }

    @Test func indentationBeforeTheFirstSpanDoesNotShiftCharacterRanges() throws {
        let timedTextMarkupLanguageContent = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
          <p begin="10.000" end="11.000">
            <span begin="10.000" end="11.000">Hi</span>
          </p>
        </div></body></tt>
        """

        let lyrics = try #require(Lyrics(ttmlContent: timedTextMarkupLanguageContent))
        let line = try #require(lyrics.lines.first)
        let timing = try #require(line.attachments.synchronizedTextTiming)

        #expect(line.content == "Hi")
        #expect(timing.words.map(\.characterRange) == [0 ..< 2])
        #expect(line.attachments.timetag?.tags.map(\.index) == [0])
    }

    @Test func characterRangesUseExtendedGraphemeClustersAcrossMixedLanguages() throws {
        let timedTextMarkupLanguageContent = """
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="und">
          <body><div><p begin="0.000" end="3.000"><span begin="0.000" end="1.000">👨‍👩‍👧‍👦</span><span begin="1.000" end="2.000">é</span><span begin="2.000" end="3.000">中</span></p></div></body>
        </tt>
        """

        let lyrics = try #require(Lyrics(ttmlContent: timedTextMarkupLanguageContent))
        let line = try #require(lyrics.lines.first)
        let timing = try #require(line.attachments.synchronizedTextTiming)

        #expect(line.content.count == 3)
        #expect(timing.words.map(\.characterRange) == [0 ..< 1, 1 ..< 2, 2 ..< 3])
        #expect(line.attachments.timetag?.tags.map(\.index) == [0, 1, 2])
    }

    @Test func spansWithoutExplicitEndsKeepTheLegacyInlineStarts() throws {
        let timedTextMarkupLanguageContent = """
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en">
          <body><div><p begin="10.000" end="12.000"><span begin="10.000">Hi</span><span begin="11.000">there</span></p></div></body>
        </tt>
        """

        let lyrics = try #require(Lyrics(ttmlContent: timedTextMarkupLanguageContent))
        let line = try #require(lyrics.lines.first)
        #expect(line.attachments.synchronizedTextTiming == nil)
        #expect(line.attachments.timetag?.tags.map(\.index) == [0, 2])
        #expect(line.attachments.timetag?.tags.map(\.time) == [0, 1])
    }
}
