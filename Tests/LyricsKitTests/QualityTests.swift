import Testing
import Foundation
import LyricsCore
@testable import LyricsService

private func makeLyrics(title: String?, artist: String?, length: Double? = nil,
                       hasTranslation: Bool = false, hasTimeTag: Bool = false) -> Lyrics {
    var lrc = "[00:00.00]hello\n[00:05.00]world\n"
    if hasTranslation {
        lrc += "[00:00.00]你好|你好\n"
    }
    let lyrics = Lyrics(lrc)!
    if let title { lyrics.idTags[.title] = title }
    if let artist { lyrics.idTags[.artist] = artist }
    if let length { lyrics.length = length }
    if hasTimeTag {
        lyrics.metadata.attachmentTags.insert(.timetag)
    }
    if hasTranslation {
        // Force translation tag explicitly — Lyrics(LRC) initialiser does pick
        // up `|` translations but the test wants to be explicit about intent.
        lyrics.metadata.attachmentTags.insert(.translation())
    }
    return lyrics
}

private func attach(_ lyrics: Lyrics, searchTitle: String, searchArtist: String,
                    duration: Double = 0) {
    let request = LyricsSearchRequest(
        searchTerm: .info(title: searchTitle, artist: searchArtist),
        duration: duration,
        limit: 5
    )
    lyrics.metadata.request = request
}

struct QualityTests {

    @Test func qualityIsFiniteForExactTitleMatch() {
        // Reproduces the historical NaN bug: title matched the search query
        // exactly while artist was unrelated. Old formula produced NaN because
        // the per-factor multiplier exceeded `qualityMixBound`, which made the
        // product negative and the cube root undefined.
        let lyrics = makeLyrics(title: "爱情讯息", artist: "郭静")
        attach(lyrics, searchTitle: "爱情讯息", searchArtist: "yihuik 苡慧")
        let quality = lyrics.quality
        #expect(quality.isFinite)
        #expect(quality >= 0 && quality <= 1.1)
    }

    @Test func qualityIsFiniteWhenAllFieldsMatch() {
        let lyrics = makeLyrics(title: "Over", artist: "yihuik 苡慧/白静晨", length: 155)
        attach(lyrics, searchTitle: "Over", searchArtist: "yihuik 苡慧/白静晨", duration: 155)
        let quality = lyrics.quality
        #expect(quality.isFinite)
        #expect(quality > 0.9)
    }

    @Test func artistMatchOutranksTitleOnlyMatch() {
        // The user's bug report: title-exact-but-wrong-artist (郭静) was
        // ranking above artist-exact-but-title-partial (yihuik 苡慧 with a
        // bracketed suffix). The new weighting must reverse that.
        let wrongArtist = makeLyrics(title: "爱情讯息", artist: "郭静")
        attach(wrongArtist, searchTitle: "爱情讯息", searchArtist: "yihuik 苡慧")

        let rightArtist = makeLyrics(title: "爱情讯息 (想念变成空气在叹息)", artist: "yihuik 苡慧")
        attach(rightArtist, searchTitle: "爱情讯息", searchArtist: "yihuik 苡慧")

        #expect(rightArtist.quality > wrongArtist.quality)
    }

    @Test func artistExactBeatsArtistUnrelated() {
        let unrelated = makeLyrics(title: "爱情讯息", artist: "容祖儿,姚晓棠")
        attach(unrelated, searchTitle: "爱情讯息", searchArtist: "yihuik 苡慧")

        let matched = makeLyrics(title: "爱情讯息", artist: "yihuik 苡慧")
        attach(matched, searchTitle: "爱情讯息", searchArtist: "yihuik 苡慧")

        #expect(matched.quality > unrelated.quality)
    }

    @Test func missingArtistTagIsPenalisedButFinite() {
        let lyrics = makeLyrics(title: "Over", artist: nil)
        attach(lyrics, searchTitle: "Over", searchArtist: "yihuik 苡慧")
        let quality = lyrics.quality
        #expect(quality.isFinite)
        #expect(quality < 0.8)
    }

    @Test func emptySearchArtistIsNeutral() {
        // When the caller does not supply an artist, two results that differ
        // only in artist text should land at the same artist score (neutral).
        let a = makeLyrics(title: "Over", artist: "Foo")
        attach(a, searchTitle: "Over", searchArtist: "")
        let b = makeLyrics(title: "Over", artist: "Bar")
        attach(b, searchTitle: "Over", searchArtist: "")
        #expect(a.quality == b.quality)
    }

    @Test func translationAndTimeTagBonusesAdd() {
        let plain = makeLyrics(title: "Over", artist: "yihuik 苡慧")
        attach(plain, searchTitle: "Over", searchArtist: "yihuik 苡慧")

        let bonused = makeLyrics(title: "Over", artist: "yihuik 苡慧",
                                 hasTranslation: true, hasTimeTag: true)
        attach(bonused, searchTitle: "Over", searchArtist: "yihuik 苡慧")

        #expect(bonused.quality > plain.quality)
        let delta = bonused.quality - plain.quality
        // Two bonuses of 0.05 each.
        #expect(abs(delta - 0.10) < 0.001)
    }

    @Test func durationCloseToQueryRanksAboveDurationFar() {
        let close = makeLyrics(title: "Over", artist: "yihuik 苡慧", length: 155)
        attach(close, searchTitle: "Over", searchArtist: "yihuik 苡慧", duration: 155)

        let far = makeLyrics(title: "Over", artist: "yihuik 苡慧", length: 240)
        attach(far, searchTitle: "Over", searchArtist: "yihuik 苡慧", duration: 155)

        #expect(close.quality > far.quality)
    }

    @Test func qualityIsCachedAfterFirstAccess() {
        let lyrics = makeLyrics(title: "Over", artist: "yihuik 苡慧")
        attach(lyrics, searchTitle: "Over", searchArtist: "yihuik 苡慧")
        let first = lyrics.quality
        // Mutating idTags would normally change the score, but the cache
        // should return the previously computed value.
        lyrics.idTags[.artist] = "completely different"
        let second = lyrics.quality
        #expect(first == second)
    }
}
