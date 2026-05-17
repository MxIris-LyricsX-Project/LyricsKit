import Foundation

enum FixtureLoader {
    enum FixtureError: Error, CustomStringConvertible {
        case notFound(String)
        case encodingFailed(String)

        var description: String {
            switch self {
            case .notFound(let name): return "Fixture not found: \(name)"
            case .encodingFailed(let name): return "Failed to decode fixture: \(name)"
            }
        }
    }

    static func data(named name: String) throws -> Data {
        let parts = name.split(separator: "/").map(String.init)
        let fileName = parts.last ?? name
        let subdirectory = parts.dropLast().joined(separator: "/")
        let full = "Fixtures/\(subdirectory.isEmpty ? "" : subdirectory + "/")\(fileName)"

        let candidates: [URL?] = [
            Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures/\(subdirectory)"),
            Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures"),
            Bundle.module.url(forResource: full, withExtension: nil),
            Bundle.module.url(forResource: fileName, withExtension: nil),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    static func string(named name: String, encoding: String.Encoding = .utf8) throws -> String {
        let data = try data(named: name)
        guard let str = String(data: data, encoding: encoding) else {
            throw FixtureError.encodingFailed(name)
        }
        return str
    }
}
