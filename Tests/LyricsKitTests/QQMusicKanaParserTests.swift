import Testing
import Foundation
import LyricsCore
@testable import LyricsService

/// Alignment rules verified against live QQMusic data (2026-06):
/// - A contiguous digit run (fullwidth １１５ or halfwidth 366) counts as a
///   single annotated unit with one reading.
/// - Latin words never consume kana segments.
struct QQMusicKanaParserTests {
    private func furiganaDescriptions(kana: String, lines: [String]) throws -> [String?] {
        var lrc = "[kana:\(kana)]\n"
        for (offset, line) in lines.enumerated() {
            lrc += String(format: "[00:%02d.00]", offset + 1) + line + "\n"
        }
        let lyrics = try #require(Lyrics(lrc))
        lyrics.applyQQMusicKanaFurigana()
        return lyrics.lines.map { $0.attachments.furigana?.description }
    }

    // Official髭男dism「115万キロのフィルム」: fullwidth digit run reads ひゃくじゅうご.
    @Test func fullwidthDigitRunConsumesOneSegment() throws {
        let result = try furiganaDescriptions(
            kana: "1ひゃくじゅうご1ま(2453,85)ん(2538,85)",
            lines: ["１１５ 万キロのフィルム"]
        )
        #expect(result == ["<ひゃくじゅうご,0,3><まん,4,5>"])
    }

    // HY「366日」: halfwidth digit run reads さんびゃくろくじゅうろく,
    // trailing Latin words consume nothing.
    @Test func halfwidthDigitRunConsumesOneSegment() throws {
        let result = try furiganaDescriptions(
            kana: "1さんびゃくろくじゅうろく1にち",
            lines: ["366日From THE FIRST TAKE"]
        )
        #expect(result == ["<さんびゃくろくじゅうろく,0,3><にち,3,4>"])
    }

    // レミオロメン「3月9日」: digits separated by kanji are independent runs.
    @Test func separatedSingleDigitsConsumeOneSegmentEach() throws {
        let result = try furiganaDescriptions(
            kana: "1さん1がつ1ここの1か",
            lines: ["３月９日"]
        )
        #expect(result == ["<さん,0,1><がつ,1,2><ここの,2,3><か,3,4>"])
    }

    @Test func digitRunAtEndOfLine() throws {
        let result = try furiganaDescriptions(
            kana: "1さんびゃくろくじゅうろく",
            lines: ["カウントは366"]
        )
        #expect(result == ["<さんびゃくろくじゅうろく,5,8>"])
    }

    // Official髭男dism「Pretender」: Latin-only words are skipped entirely.
    @Test func latinWordsDoNotConsumeSegments() throws {
        let result = try furiganaDescriptions(
            kana: "1ひげ1だん",
            lines: ["Pretender - Official髭男dism"]
        )
        #expect(result == ["<ひげ,20,21><だん,21,22>"])
    }

    // 115万キロのフィルム「愛しい日々尊い日々」: the repetition mark 々 is an
    // independent base unit carrying its own reading (日々 = ひ + び).
    @Test func repetitionMarkIsIndependentBaseUnit() throws {
        let result = try furiganaDescriptions(
            kana: "1いと1ひ1び1とうと1ひ1び",
            lines: ["愛しい日々尊い日々"]
        )
        #expect(result == ["<いと,0,1><ひ,3,4><び,4,5><とうと,5,6><ひ,7,8><び,8,9>"])
    }

    // Fullwidth Latin (ＴＶ) and halfwidth katakana (ｷﾗｷﾗ) behave like their
    // counterparts: neither is a base unit, neither consumes a segment.
    @Test func fullwidthLatinAndHalfwidthKatakanaAreSkipped() throws {
        let result = try furiganaDescriptions(
            kana: "1おん1がく1ひか",
            lines: ["ＴＶの音楽ｷﾗｷﾗ光る"]
        )
        #expect(result == ["<おん,3,4><がく,4,5><ひか,9,10>"])
    }

    // 115万キロのフィルム「エンドロールなんてもん」: a kana-only line yields no
    // furigana and must not steal the next line's readings.
    @Test func kanaOnlyLineConsumesNothing() throws {
        let result = try furiganaDescriptions(
            kana: "1つく",
            lines: [
                "エンドロールなんてもん",
                "作りたくもないから",
            ]
        )
        #expect(result == [nil, "<つく,0,1>"])
    }

    // 丸ノ内サディスティック「リッケン６２０頂戴」: an empty-reading unit (bare
    // count digit) consumes the unannotated digit run without emitting furigana.
    @Test func emptyReadingUnitConsumesDigitRunSilently() throws {
        let result = try furiganaDescriptions(
            kana: "11ちょう1だい",
            lines: ["リッケン６２０頂戴"]
        )
        #expect(result == ["<ちょう,7,8><だい,8,9>"])
    }

    // 丸ノ内サディスティック title: empty-reading units also consume kanji bases
    // (the translated title 丸内虐待狂 gets no readings).
    @Test func emptyReadingUnitsConsumeKanjiBases() throws {
        let result = try furiganaDescriptions(
            kana: "1まる1うち111111しい1な1りん1ご",
            lines: ["丸の内サディスティック (丸内虐待狂) - 椎名林檎"]
        )
        #expect(result == ["<まる,0,1><うち,2,3><しい,22,23><な,23,24><りん,24,25><ご,25,26>"])
    }

    // Regression for the cumulative off-by-one shift: digit runs in early lines
    // must not steal readings from later lines (115万キロのフィルム, first verse).
    @Test func digitRunsDoNotShiftReadingsAcrossLines() throws {
        let result = try furiganaDescriptions(
            kana: "1ひゃくじゅうご1まん1ひげ1だん1し1ふじ1はら1さとし1きょく1ふじ1はら1さとし"
                + "1うた1きょく1ない1よう1ぼく1あたま1なか",
            lines: [
                "１１５ 万キロのフィルム - Official髭男dism",
                "词：藤原聡",
                "曲：藤原聡",
                "これから歌う曲の内容は",
                "僕の頭の中のこと",
            ]
        )
        #expect(result == [
            "<ひゃくじゅうご,0,3><まん,4,5><ひげ,23,24><だん,24,25>",
            "<し,0,1><ふじ,2,3><はら,3,4><さとし,4,5>",
            "<きょく,0,1><ふじ,2,3><はら,3,4><さとし,4,5>",
            "<うた,4,5><きょく,6,7><ない,8,9><よう,9,10>",
            "<ぼく,0,1><あたま,2,3><なか,4,5>",
        ])
    }
}

/// End-to-end checks over real QQMusic responses (downloaded 2026-06, raw
/// encrypted XML) covering the full pipeline: decrypt → QRC parse → kana
/// furigana. Each fixture exercises a distinct mix of character classes.
struct QQMusicKanaFixtureTests {
    private func fetchLyrics(fixture: String) async throws -> Lyrics {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search1.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search2.json")))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/\(fixture)")))
        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let request = LyricsSearchRequest(
            searchTerm: .info(title: "Test Song", artist: "Test Artist"),
            duration: 200,
            limit: 5
        )
        let lyrics = try await collect(provider.lyrics(for: request))
        return try #require(lyrics.first)
    }

    private func furigana(_ lyrics: Lyrics, _ content: String) -> String?? {
        lyrics.lines.first { $0.content == content }
            .map { $0.attachments.furigana?.description }
    }

    // Official髭男dism「115万キロのフィルム」: fullwidth digit runs (１１５/１０)
    // at three positions, 々, katakana-only lines, Latin words in the title.
    @Test func fullwidthDigitsAcrossWholeSong() async throws {
        let lyrics = try await fetchLyrics(fixture: "lyrics_kana_115man_kilo.xml")
        #expect(furigana(lyrics, "１１５ 万キロのフィルム - Official髭男dism (Official Hige Dandism)")
            == "<ひゃくじゅうご,0,3><まん,4,5><ひげ,23,24><だん,24,25>")
        #expect(furigana(lyrics, "主演はもちろん君で") == "<しゅ,0,1><えん,1,2><きみ,7,8>")
        #expect(furigana(lyrics, "きっと１０年後くらいには") == "<じゅう,3,5><ねん,5,6><ご,6,7>")
        #expect(furigana(lyrics, "ざっと１１５万キロ") == "<ひゃくじゅうご,3,6><まん,6,7>")
        #expect(furigana(lyrics, "愛しい日々尊い日々")
            == "<いと,0,1><ひ,3,4><び,4,5><とうと,5,6><ひ,7,8><び,8,9>")
        #expect(furigana(lyrics, "この命ある限り") == "<いのち,2,3><かぎ,5,6>")
        #expect(furigana(lyrics, "エンドロールなんてもん") == .some(nil))
    }

    // レミオロメン「3月9日」: fullwidth single digits separated by kanji.
    @Test func fullwidthSingleDigitDates() async throws {
        let lyrics = try await fetchLyrics(fixture: "lyrics_kana_sangatsu_kokonoka.xml")
        #expect(furigana(lyrics, "３月９日 - Remioromen (レミオロメン)")
            == "<さん,0,1><がつ,1,2><ここの,2,3><か,3,4>")
        #expect(furigana(lyrics, "３月の風に想いをのせて")
            == "<さん,0,1><がつ,1,2><かぜ,3,4><おも,5,6>")
    }

    // HY「366日」: halfwidth digit run with a reading, Latin words in the title.
    @Test func halfwidthDigitRunWithReading() async throws {
        let lyrics = try await fetchLyrics(fixture: "lyrics_kana_366nichi.xml")
        #expect(furigana(lyrics, "366日 (From THE FIRST TAKE) - HY (エイチワイ)")
            == "<さんびゃくろくじゅうろく,0,3><にち,3,4>")
        #expect(furigana(lyrics, "戻れないと知ってても") == "<もど,0,1><し,5,6>")
    }

    // 椎名林檎「丸ノ内サディスティック」: empty-reading units over the translated
    // title (丸内虐待狂) and an unannotated digit run (６２０), literal
    // parentheses preserved by the QRC parser, annotated digit run (１９).
    @Test func emptyReadingUnitsAndLiteralParentheses() async throws {
        let lyrics = try await fetchLyrics(fixture: "lyrics_kana_marunouchi.xml")
        #expect(furigana(lyrics, "丸の内サディスティック (丸内虐待狂) - 椎名林檎 (しいな りんご)")
            == "<まる,0,1><うち,2,3><しい,22,23><な,23,24><りん,24,25><ご,25,26>")
        #expect(furigana(lyrics, "リッケン６２０頂戴") == "<ちょう,7,8><だい,8,9>")
        #expect(furigana(lyrics, "１９万も持って居ない 御茶の水")
            == "<じゅうきゅう,0,2><まん,2,3><も,4,5><い,7,8><お,11,12><ちゃ,12,13><みず,14,15>")
    }

    // After the Rain「1・2・3」: halfwidth digits and simplified-Chinese title
    // characters all consumed by empty-reading units ("3 (" restored by the
    // QRC literal-paren fix), hiragana-only credit values.
    @Test func unannotatedTitleDigitsDoNotShiftSong() async throws {
        let lyrics = try await fetchLyrics(fixture: "lyrics_kana_123.xml")
        #expect(furigana(lyrics, "1・2・3 (《神奇宝贝》TV动画片头曲) - After the Rain") == .some(nil))
        #expect(furigana(lyrics, "词：まふまふ") == "<し,0,1>")
        #expect(furigana(lyrics, "编曲：まふまふ") == "<きょく,1,2>")
        #expect(furigana(lyrics, "出かける準備はできたかい？") == "<で,0,1><じゅん,4,5><び,5,6>")
        #expect(furigana(lyrics, "キミに見せたい不思議の世界")
            == "<み,3,4><ふ,7,8><し,8,9><ぎ,9,10><せ,11,12><かい,12,13>")
    }
}
