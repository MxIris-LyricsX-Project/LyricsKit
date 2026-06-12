import Foundation
import LyricsCore
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    final class QQMusic {
        let httpClient: HTTPClient
        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        private static let searchHost1 = "c.y.qq.com"
        private static let searchPath1 = "/splcloud/fcgi-bin/smartbox_new.fcg"
        private static let searchHost2 = "u.y.qq.com"
        private static let searchPath2 = "/cgi-bin/musicu.fcg"
        private static let lyricsHost = "c.y.qq.com"
        private static let lyricsPath = "/qqmusic/fcgi-bin/lyric_download.fcg"

        init(httpClient: HTTPClient = .shared) {
            self.httpClient = httpClient
        }
    }
}

extension LyricsProviders.QQMusic: _LyricsProvider {
    struct LyricsToken {
        let value: QQMusicSongSearchResult
    }

    static let service: String = "QQMusic"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let combined = await withTaskGroup(of: [LyricsToken].self) { group in
            group.addTask { await self.searchApi1(for: request) }
            group.addTask { await self.searchApi2(for: request) }

            var collected: [LyricsToken] = []
            for await results in group {
                collected.append(contentsOf: results)
            }
            return collected
        }
        if combined.isEmpty {
            throw LyricsProviderError.processingFailed(reason: "QQMusic search returned no candidates from any endpoint.")
        }
        return combined
    }

    private func searchApi1(for request: LyricsSearchRequest) async -> [LyricsToken] {
        let endpoint = Endpoint(
            host: Self.searchHost1,
            path: Self.searchPath1,
            queryItems: [URLQueryItem(name: "key", value: request.searchTerm.description)]
        )
        do {
            let result: QQResponseSearchResult = try await performer.performJSON(endpoint)
            return result.data.song.list.map { LyricsToken(value: $0) }
        } catch {
            #log(.error, "QQMusic search API 1 failed: \(error)")
            return []
        }
    }

    /// Search via the musicu endpoint (POST JSON).
    private func searchApi2(for request: LyricsSearchRequest) async -> [LyricsToken] {
        let requestBody: [String: Any] = [
            "req_1": [
                "method": "DoSearchForQQMusicDesktop",
                "module": "music.search.SearchCgiService",
                "param": [
                    "num_per_page": 20,
                    "page_num": 1,
                    "query": request.searchTerm.description,
                    "search_type": 0,
                ],
            ],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return [] }
        let endpoint = Endpoint(
            host: Self.searchHost2,
            path: Self.searchPath2,
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: bodyData
        )
        do {
            let result: QQResponseSearchResult2 = try await performer.performJSON(endpoint)
            guard result.request.code == 0 else { return [] }
            return result.request.data.body.song.list.map { LyricsToken(value: $0) }
        } catch {
            #log(.error, "QQMusic search API 2 failed: \(error)")
            return []
        }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        let songToken = token.value
        let formBody = "musicid=\(songToken.id)&version=15&miniversion=82&lrctype=4"
        guard let bodyData = formBody.data(using: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Could not encode QQMusic form body.")
        }
        let endpoint = Endpoint(
            host: Self.lyricsHost,
            path: Self.lyricsPath,
            method: .post,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://c.y.qq.com/",
            ],
            body: bodyData
        )

        let data = try await performer.performData(endpoint)
        guard var dataString = String(data: data, encoding: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Could not convert data to string.")
        }
        dataString = dataString
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")

        guard let xmlDocument = try? XMLUtils.create(content: dataString) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse QQMusic XML response.")
        }

        let decodedContents = QQMusicXMLDecoder.decodeLyricContents(from: xmlDocument)
        guard let origContent = decodedContents["orig"] else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse or decrypt QQMusic QRC lyrics.")
        }

        let normalizedOrigContent = QQMusicXMLDecoder.normalizeExtendedLrcTimestamps(origContent)
        guard let lrc = Lyrics(qqmusicQrcContent: origContent)
            ?? Lyrics(normalizedOrigContent)
            ?? Lyrics(origContent) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse or decrypt QQMusic QRC lyrics.")
        }
        lrc.applyQQMusicKanaFurigana()

        if let transContent = decodedContents["ts"], let transLrc = Lyrics(transContent) {
            lrc.merge(translation: transLrc)
        }

        lrc.applyMetadata(
            title: songToken.name,
            artist: songToken.singers.joined(separator: ","),
            artworkURL: await fetchAlbumCoverURL(songMid: songToken.mid),
            serviceToken: "\(songToken.mid)"
        )
        return lrc
    }

    private func fetchAlbumCoverURL(songMid: String) async -> URL? {
        let requestBody: [String: Any] = [
            "comm": ["ct": 24, "cv": 0],
            "songinfo": [
                "module": "music.pf_song_detail_svr",
                "method": "get_song_detail_yqq",
                "param": ["song_mid": songMid],
            ],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        let endpoint = Endpoint(
            host: Self.searchHost2,
            path: Self.searchPath2,
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: bodyData
        )
        guard let response: QQResponseSongDetail = try? await performer.performJSON(endpoint),
              !response.songinfo.data.trackInfo.album.mid.isEmpty else {
            return nil
        }
        let albumMid = response.songinfo.data.trackInfo.album.mid
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R800x800M000\(albumMid).jpg")
    }
}
