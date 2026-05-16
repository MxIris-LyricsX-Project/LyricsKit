import Foundation
import LyricsCore

private let kugouSearchBaseURLString = "http://lyrics.kugou.com/search"
private let kugouLyricsBaseURLString = "http://lyrics.kugou.com/download"

extension LyricsProviders {
    final class Kugou {
        init() {}
    }
}

extension LyricsProviders.Kugou: _LyricsProvider {
    struct LyricsToken {
        let value: KugouResponseSearchResult.Data.Info
    }

    static let service: String = "Kugou"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
//        let parameter: [String: Any] = [
//            "keyword": request.searchTerm.description,
//            "duration": Int(request.duration * 1000),
//            "client": "pc",
//            "ver": 1,
//            "man": "yes",
//        ]

        let urlString = "http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=\(request.searchTerm.description)&page=1&pagesize=20&showtype=1"
//        let urlString = kugouSearchBaseURLString + "?" + parameter.stringFromHttpParameters
        guard let url = URL(string: urlString) else {
            throw LyricsProviderError.invalidURL(urlString: urlString)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let searchResult = try JSONDecoder().decode(KugouResponseSearchResult.self, from: data)

            return searchResult.data.info.map { .init(value: $0) }

//            return searchResult.candidates.map(LyricsToken.init)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        let url = URL(string: "https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=&hash=\(token.value.hash)&album_audio_id=\(token.value.albumAudioID)")!

        let (candidatesData, _) = try await URLSession.shared.data(for: .init(url: url))

        guard let candidate = try JSONDecoder().decode(KugouResponseSearchResultCandidates.self, from: candidatesData).candidates.first else {
            throw LyricsProviderError.processingFailed(reason: "No candidates found for the provided token.")
        }

        let parameter: [String: Any] = [
            "id": candidate.id,
            "accesskey": candidate.accesskey,
            "fmt": "krc",
            "charset": "utf8",
            "client": "pc",
            "ver": 1,
        ]

        let urlString = kugouLyricsBaseURLString + "?" + parameter.stringFromHttpParameters
        guard let url = URL(string: urlString) else {
            throw LyricsProviderError.invalidURL(urlString: urlString)
        }

        let singleLyricsResponse: KugouResponseSingleLyrics
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            singleLyricsResponse = try JSONDecoder().decode(KugouResponseSingleLyrics.self, from: data)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }

        guard let lrcContent = decryptKugouKrc(singleLyricsResponse.content) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to decrypt KRC content.")
        }

        guard let lrc = Lyrics(kugouKrcContent: lrcContent) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to initialize Lyrics from KRC content.")
        }

        lrc.idTags[.title] = candidate.song
        lrc.idTags[.artist] = candidate.singer
        lrc.idTags[.lrcBy] = "Kugou"
        lrc.length = Double(candidate.duration) / 1000

        if let unionCover = token.value.transParam?.unionCover {
            let coverURLString = unionCover.replacingOccurrences(of: "{size}", with: "480")
            lrc.metadata.artworkURL = URL(string: coverURLString)
        }

        lrc.metadata.serviceToken = "\(candidate.id),\(candidate.accesskey)"

        return lrc
    }

    func randomString(length: Int, characters: String) -> String {
        return String((0 ..< length).map { _ in
            characters.randomElement()!
        })
    }
}
