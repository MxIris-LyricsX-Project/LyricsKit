import Testing
import Foundation
import LyricsCore
@testable import LyricsService

struct QQMusicQrcParserTests {
    // A QRC token whose text contains a literal "(" (e.g. "3 (") must keep the
    // text instead of dropping the whole fragment (丸ノ内サディスティック and
    // 1・2・3 titles regressed this way).
    @Test func literalParenthesesSurviveInlineTimeTags() throws {
        let content = "[100,2000]3 ((100,100)テスト(200,100))(300,100)"
        let lyrics = try #require(Lyrics(qqmusicQrcContent: content))
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].content == "3 (テスト)")
    }

    @Test func plainTokensStillParse() throws {
        let content = "[0,3000]歌(0,500)詞(500,500) (1000,100)テスト(1100,900)"
        let lyrics = try #require(Lyrics(qqmusicQrcContent: content))
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].content == "歌詞 テスト")
    }
}
