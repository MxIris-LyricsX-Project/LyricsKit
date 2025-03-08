import Foundation

struct LRCLIBRepsonse: Decodable {
    struct LyricLine: Decodable, Hashable {
        let startTimeMS: TimeInterval
        let words: String
        let id = UUID()

        enum CodingKeys: String, CodingKey {
            case startTimeMS = "startTimeMs"
            case words
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.startTimeMS = try TimeInterval(container.decode(String.self, forKey: .startTimeMS))!
            self.words = try container.decode(String.self, forKey: .words)
        }

        init(startTime: TimeInterval, words: String) {
            self.startTimeMS = startTime
            self.words = words
        }
    }

    let id: Int
    let name, trackName, artistName, albumName: String
    let duration: Int
    let instrumental: Bool
    let plainLyrics, syncedLyrics: String
    let lyrics: [LyricLine]

    enum CodingKeys: CodingKey {
        case id
        case name
        case trackName
        case artistName
        case albumName
        case duration
        case instrumental
        case plainLyrics
        case syncedLyrics
//        case lyrics
    }

    static func decodeLyrics(input: String) -> [LyricLine] {
        var lyricsArray: [LyricLine] = []
        let lines = input.components(separatedBy: "\n")

        for line in lines {
            // Use regex to match the timestamp and the lyrics
            let regex = try! NSRegularExpression(pattern: #"\[(\d{2}:\d{2}\.\d{2})\]\s*(.*)"#)
            let matches = regex.matches(in: line, range: NSRange(line.startIndex ..< line.endIndex, in: line))

            for match in matches {
                if let timestampRange = Range(match.range(at: 1), in: line),
                   let lyricsRange = Range(match.range(at: 2), in: line) {
                    let timestamp = String(line[timestampRange])
                    let lyrics = String(line[lyricsRange])
                    lyricsArray.append(LyricLine(startTime: timestamp.convertToTimeInterval(), words: lyrics))
                }
            }
        }

        return lyricsArray
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.trackName = try container.decode(String.self, forKey: .trackName)
        self.artistName = try container.decode(String.self, forKey: .artistName)
        self.albumName = try container.decode(String.self, forKey: .albumName)
        self.duration = try container.decode(Int.self, forKey: .duration)
        self.instrumental = try container.decode(Bool.self, forKey: .instrumental)
        if instrumental {
            self.plainLyrics = ""
            self.syncedLyrics = ""
            self.lyrics = []
        } else {
            self.plainLyrics = try container.decode(String.self, forKey: .plainLyrics)
            self.syncedLyrics = try container.decode(String.self, forKey: .syncedLyrics)
            self.lyrics = Self.decodeLyrics(input: syncedLyrics)
        }
    }
}

extension String {
    fileprivate func convertToTimeInterval() -> TimeInterval {
        guard self != "" else {
            return 0
        }

        var interval: Double = 0

        let parts = self.components(separatedBy: ":")
        for (index, part) in parts.reversed().enumerated() {
            interval += (Double(part) ?? 0) * pow(Double(60), Double(index))
        }

        return interval * 1000 // Convert seconds to milliseconds
    }
}
