import Foundation
import LyricsCore

extension Lyrics {
    func applyMetadata(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        lrcBy: String? = nil,
        length: Double? = nil,
        artworkURL: URL? = nil,
        serviceToken: String? = nil
    ) {
        if let title { idTags[.title] = title }
        if let artist { idTags[.artist] = artist }
        if let album { idTags[.album] = album }
        if let lrcBy { idTags[.lrcBy] = lrcBy }
        if let length { self.length = length }
        if let artworkURL { metadata.artworkURL = artworkURL }
        if let serviceToken { metadata.serviceToken = serviceToken }
    }
}
