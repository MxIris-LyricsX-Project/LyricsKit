import Foundation
import LyricsCore

// Weighted average of artist / title / duration similarity, each clamped to
// [0, 1]. Artist outweighs title so that a result whose artist matches the
// query but whose title is only a substring (e.g. "Song Title (Live)") still
// ranks above a result whose title is exact but artist is unrelated.
private let artistWeight = 0.45
private let titleWeight = 0.40
private let durationWeight = 0.15

private let translationBonus = 0.05
private let inlineTimeTagBonus = 0.05

// Neutral score returned when the search side or the lyrics side did not
// supply the field — neither reward nor penalty.
private let neutralScore = 0.6
// The lyrics did declare a field but the user provided a non-empty query for
// it; a missing tag is a mild negative signal, not silence.
private let missingTagScore = 0.3
// Floor for duration when the absolute delta is >= 10 seconds.
private let minimalDurationQuality = 0.5

// Subtracted when the candidate's title looks like an instrumental /
// karaoke / off-vocal variant but the user wasn't asking for one. Sized
// to outweigh the small similarity tie between "Song" and "Song (伴奏)"
// without sinking the candidate so far that it disappears.
private let alternateVersionPenalty = 0.3

// Title fragments that mark an accompaniment / off-vocal variant users
// almost never want lyrics for. Matched case-insensitively as substrings,
// so "(Instrumental)", "Karaoke ver.", and "纯音乐版" all trigger.
// Single-word abbreviations like "MR" are intentionally left out because
// they collide with normal song titles ("Mr. Brightside").
private let alternateVersionKeywords: [String] = [
    "伴奏", "无人声", "纯音乐", "卡拉ok", "伴唱",
    "instrumental", "inst.", "karaoke",
    "off vocal", "off-vocal", "offvocal",
    "acapella", "a capella",
]

extension Lyrics {
    public var quality: Double {
        if let cached = metadata.quality {
            return cached
        }
        let base = artistQuality * artistWeight
                 + titleQuality * titleWeight
                 + durationQuality * durationWeight
        var quality = max(0.0, min(1.0, base))
        if metadata.hasTranslation {
            quality += translationBonus
        }
        if metadata.attachmentTags.contains(.timetag) {
            quality += inlineTimeTagBonus
        }
        if isUnwantedAlternateVersion {
            quality -= alternateVersionPenalty
        }
        metadata.quality = quality
        return quality
    }

    /// True when the lyrics' title carries an alternate-version marker
    /// (instrumental, karaoke, off-vocal, …) that the search request did
    /// not also ask for. Pushes accompaniment lyrics behind the real
    /// vocal version when both come back for the same song.
    private var isUnwantedAlternateVersion: Bool {
        guard let title = idTags[.title] else { return false }
        let titleLowered = title.lowercased()
        guard alternateVersionKeywords.contains(where: { titleLowered.contains($0) }) else {
            return false
        }
        let searchText: String
        switch metadata.request?.searchTerm {
        case .info(let searchTitle, _)?:
            searchText = searchTitle.lowercased()
        case .keyword(let keyword)?:
            searchText = keyword.lowercased()
        case nil:
            return true
        }
        return !alternateVersionKeywords.contains(where: { searchText.contains($0) })
    }

    public func isMatched() -> Bool {
        guard let artist = idTags[.artist],
              let title = idTags[.title] else {
            return false
        }
        switch metadata.request?.searchTerm {
        case .info(let searchTitle, let searchArtist)?:
            return title.isCaseInsensitiveSimilar(to: searchTitle)
                && artist.isCaseInsensitiveSimilar(to: searchArtist)
        case .keyword(let keyword)?:
            return title.isCaseInsensitiveSimilar(to: keyword)
                && artist.isCaseInsensitiveSimilar(to: keyword)
        case nil:
            return false
        }
    }

    private var artistQuality: Double {
        switch metadata.request?.searchTerm {
        case .info(_, let searchArtist)?:
            guard !searchArtist.isEmpty else { return neutralScore }
            guard let artist = idTags[.artist], !artist.isEmpty else { return missingTagScore }
            return clampedSimilarity(artist.lowercased(), searchArtist.lowercased())
        case .keyword(let keyword)?:
            guard let artist = idTags[.artist], !artist.isEmpty else { return neutralScore }
            return clampedContainmentSimilarity(artist.lowercased(), in: keyword.lowercased())
        case nil:
            return neutralScore
        }
    }

    private var titleQuality: Double {
        switch metadata.request?.searchTerm {
        case .info(let searchTitle, _)?:
            guard !searchTitle.isEmpty else { return neutralScore }
            guard let title = idTags[.title], !title.isEmpty else { return missingTagScore }
            return clampedSimilarity(title.lowercased(), searchTitle.lowercased())
        case .keyword(let keyword)?:
            guard let title = idTags[.title], !title.isEmpty else { return neutralScore }
            return clampedContainmentSimilarity(title.lowercased(), in: keyword.lowercased())
        case nil:
            return neutralScore
        }
    }

    private var durationQuality: Double {
        guard let duration = length,
              let searchDuration = metadata.request?.duration, searchDuration > 0 else {
            return neutralScore
        }
        let dt = abs(searchDuration - duration)
        guard dt < 10 else {
            return minimalDurationQuality
        }
        return 1 - pow(dt / 10, 2) * (1 - minimalDurationQuality)
    }
}

extension String {
    fileprivate func distance(to other: String, substitutionCost: Int = 1, insertionCost: Int = 1, deletionCost: Int = 1) -> Int {
        var d = Array(0 ... other.count)
        var t = 0
        for c1 in self {
            t = d[0]
            d[0] += 1
            for (i, c2) in other.enumerated() {
                let t2 = d[i + 1]
                if c1 == c2 {
                    d[i + 1] = t
                } else {
                    d[i + 1] = Swift.min(t + substitutionCost, d[i] + insertionCost, t2 + deletionCost)
                }
                t = t2
            }
        }
        return d.last!
    }

    fileprivate func isCaseInsensitiveSimilar(to string: String) -> Bool {
        let s1 = lowercased()
        let s2 = string.lowercased()
        return s1.contains(s2) || s2.contains(s1)
    }
}

private func clampedSimilarity(_ a: String, _ b: String) -> Double {
    return max(0.0, min(1.0, similarity(s1: a, s2: b)))
}

private func clampedContainmentSimilarity(_ a: String, in b: String) -> Double {
    return max(0.0, min(1.0, similarity(s1: a, in: b)))
}

private func similarity(s1: String, s2: String) -> Double {
    let len = min(s1.count, s2.count)
    guard len > 0 else { return 0 }
    let diff = min(s1.distance(to: s2, insertionCost: 0), s1.distance(to: s2, deletionCost: 0))
    return Double(len - diff) / Double(len)
}

private func similarity(s1: String, in s2: String) -> Double {
    let len = max(s1.count, s2.count)
    guard len > 0 else { return 1 }
    let diff = s1.distance(to: s2, insertionCost: 0)
    return Double(len - diff) / Double(len)
}
