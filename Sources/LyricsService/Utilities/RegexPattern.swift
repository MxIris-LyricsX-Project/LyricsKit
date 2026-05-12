import Foundation
import Regex

// swiftlint:disable force_try
private let timeTagRegex = Regex(#"\[([-+]?\d+):(\d+(?:\.\d+)?)\]"#)

func resolveTimeTag(_ str: String) -> [TimeInterval] {
    let matchs = timeTagRegex.matches(in: str)
    return matchs.map { match in
        let min = Double(match[1]!.content)!
        let sec = Double(match[2]!.content)!
        return min * 60 + sec
    }
}

let id3TagRegex = try! Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"#, options: .anchorsMatchLines)

let krcLineRegex = try! Regex(#"^\[(\d+),(\d+)\](.*)"#, options: .anchorsMatchLines)

let qrcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"#, options: [.anchorsMatchLines])

let netEaseYrcInlineTagRegex = Regex(#"\((\d+),(\d+),0\)([^(]*)"#)

let netEaseInlineTagRegex = Regex(#"\(0,(\d+)\)([^(]+)(\(0,1\) )?"#)

let kugouInlineTagRegex = Regex(#"<(\d+),(\d+),0>([^<]*)"#)

let qqmusicInlineTagRegex = Regex(#"([^(]*)\((\d+),(\d+)\)"#)
// swiftlint:enable force_try
