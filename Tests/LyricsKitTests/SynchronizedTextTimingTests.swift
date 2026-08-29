import Foundation
import LyricsCore
import Testing

struct SynchronizedTextTimingTests {
    @Test func timingRoundTripsThroughLyricsDescription() throws {
        let timing = LyricsLine.Attachments.SynchronizedTextTiming(
            words: [
                .init(
                    characterRange: 0 ..< 5,
                    timeRange: 0.125 ..< 1.625,
                    syllables: [
                        .init(characterRange: 0 ..< 2, timeRange: 0.125 ..< 0.625),
                        .init(characterRange: 2 ..< 5, timeRange: 0.625 ..< 1.625),
                    ]
                ),
            ],
            duration: 2
        )
        var attachments = LyricsLine.Attachments()
        attachments.synchronizedTextTiming = timing
        let lyrics = Lyrics(
            lines: [LyricsLine(content: "Hello", position: 12, attachments: attachments)],
            idTags: [:]
        )

        let serializedLyrics = lyrics.description
        #expect(serializedLyrics.contains("[synchronized-timing]1:"))

        let reparsedLyrics = try #require(Lyrics(serializedLyrics))
        #expect(reparsedLyrics.lines[0].attachments.synchronizedTextTiming == timing)
        #expect(reparsedLyrics.metadata.attachmentTags.contains(.synchronizedTextTiming))
    }

    @Test func malformedPayloadIsIgnoredWithoutAffectingTheLyricLine() throws {
        let serializedLyrics = """
        [00:12.000]Hello
        [00:12.000][synchronized-timing]1:not-base-64
        """

        let lyrics = try #require(Lyrics(serializedLyrics))
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].content == "Hello")
        #expect(lyrics.lines[0].attachments.synchronizedTextTiming == nil)
    }

    @Test func characterRangeBeyondTheLineIsDiscardedAfterLoading() throws {
        let invalidTiming = LyricsLine.Attachments.SynchronizedTextTiming(
            words: [
                .init(characterRange: 0 ..< 8, timeRange: 0 ..< 1),
            ],
            duration: 1
        )
        let serializedLyrics = """
        [00:12.000]Hello
        [00:12.000][synchronized-timing]\(invalidTiming)
        """

        let lyrics = try #require(Lyrics(serializedLyrics))
        #expect(lyrics.lines[0].attachments.synchronizedTextTiming == nil)
        #expect(!lyrics.metadata.attachmentTags.contains(.synchronizedTextTiming))
    }

    @Test func unknownPayloadVersionFallsBackToLegacyTiming() throws {
        let serializedLyrics = """
        [00:12.000]Hello
        [00:12.000][tt]<0,0><1000>
        [00:12.000][synchronized-timing]99:e30=
        """

        let lyrics = try #require(Lyrics(serializedLyrics))
        #expect(lyrics.lines[0].attachments.synchronizedTextTiming == nil)
        #expect(lyrics.lines[0].attachments.timetag?.tags.first?.index == 0)
        #expect(lyrics.lines[0].attachments.timetag?.duration == 1)
    }

    @Test func legacyInlineTimingDoesNotInventStructuredTiming() throws {
        let serializedLyrics = """
        [00:12.000]Hello
        [00:12.000][tt]<0,0><500,2><1000>
        """

        let lyrics = try #require(Lyrics(serializedLyrics))
        #expect(lyrics.lines[0].attachments.synchronizedTextTiming == nil)
        #expect(lyrics.lines[0].attachments.timetag?.tags.count == 2)
    }

    @Test func reversedSerializedRangesAreRejectedWithoutConstructingAnInvalidRange() throws {
        let malformedPayload = """
        {"durationMilliseconds":1000,"words":[{"endingCharacterIndex":1,"endingTimeMilliseconds":1000,"startingCharacterIndex":5,"startingTimeMilliseconds":0,"syllables":[]}]}
        """
        let encodedPayload = Data(malformedPayload.utf8).base64EncodedString()
        let serializedLyrics = """
        [00:12.000]Hello
        [00:12.000][tt]<0,0><1000>
        [00:12.000][synchronized-timing]1:\(encodedPayload)
        """

        let lyrics = try #require(Lyrics(serializedLyrics))
        #expect(lyrics.lines[0].attachments.synchronizedTextTiming == nil)
        #expect(lyrics.lines[0].attachments.timetag != nil)
    }
}
