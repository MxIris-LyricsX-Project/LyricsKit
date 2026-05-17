import Foundation
import LyricsCore
import Regex
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    final class NetEase {
        let httpClient: HTTPClient
        private let eapiClient: NetEaseEapiClient
        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        private static let lyricsEapiURL = "https://interface3.music.163.com/eapi/song/lyric/v1"

        init(httpClient: HTTPClient = .shared) {
            self.httpClient = httpClient
            self.eapiClient = NetEaseEapiClient(httpClient: httpClient)
        }
    }
}

extension LyricsProviders.NetEase: _LyricsProvider {
    struct LyricsToken {
        let value: NetEaseResponseSearchResult.Result.Song
    }

    static let service: String = "NetEase"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let endpoint = Endpoint(
            scheme: "http",
            host: "music.163.com",
            path: "/api/search/pc",
            queryItems: [
                URLQueryItem(name: "s", value: request.searchTerm.description),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "type", value: "1"),
            ],
            method: .post,
            headers: [
                "Referer": "http://music.163.com/",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15",
            ]
        )

        // First pass to extract Set-Cookie. Use `value(forHTTPHeaderField:)` so the
        // lookup is case-insensitive and works under FoundationNetworking too.
        var request1 = try endpoint.buildRequest()
        let (_, firstResponse) = try await performer.execute(request1)
        if let setCookie = firstResponse.value(forHTTPHeaderField: "Set-Cookie"),
           let cookieIdx = setCookie.firstIndex(of: ";") {
            request1.setValue(String(setCookie[..<cookieIdx]), forHTTPHeaderField: "Cookie")
        }

        // Second pass with cookie.
        let data = try await performer.executeReturningData(request1)
        let searchResult: NetEaseResponseSearchResult = try performer.decode(data, as: NetEaseResponseSearchResult.self)
        return searchResult.result.songs.map(LyricsToken.init)
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        let payload: [String: String] = [
            "id": token.value.id.description,
            "cp": "false",
            "lv": "0",
            "kv": "0",
            "tv": "0",
            "rv": "0",
            "yv": "0",
            "ytv": "0",
            "yrv": "0",
            "csrf_token": "",
        ]

        let raw = try await eapiClient.post(url: Self.lyricsEapiURL, payload: payload)
        let singleLyricsResponse: NetEaseResponseSingleLyrics =
            try performer.decode(raw, as: NetEaseResponseSingleLyrics.self)

        let lyrics: Lyrics
        let transLrc = (singleLyricsResponse.tlyric?.fixedLyric).flatMap(Lyrics.init(_:))
        if let yrc = singleLyricsResponse.yrc?.fixedLyric, let parsed = Lyrics(netEaseYrcContent: yrc) {
            lyrics = parsed
        } else if let kLrc = (singleLyricsResponse.klyric?.fixedLyric).flatMap(Lyrics.init(netEaseKLyricContent:)) {
            transLrc.map(kLrc.forceMerge)
            lyrics = kLrc
        } else if let lrc = (singleLyricsResponse.lrc?.fixedLyric).flatMap(Lyrics.init(_:)) {
            transLrc.map(lrc.merge)
            lyrics = lrc
        } else {
            throw LyricsProviderError.processingFailed(reason: "No valid lyric content found in NetEase response.")
        }

        lyrics.applyMetadata(
            title: token.value.name,
            artist: token.value.artists.first?.name,
            album: token.value.album.name,
            lrcBy: singleLyricsResponse.lyricUser?.nickname,
            length: Double(token.value.duration) / 1000,
            artworkURL: token.value.album.picUrl,
            serviceToken: "\(token.value.id)"
        )
        return lyrics
    }
}

private let netEaseTimeTagFixer = Regex(#"(\[\d+:\d+):(\d+\])"#)

extension NetEaseResponseSingleLyrics.Lyric {
    fileprivate var fixedLyric: String? {
        lyric?.replacingMatches(of: netEaseTimeTagFixer, with: "$1.$2")
    }
}
