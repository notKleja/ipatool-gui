import Foundation

/// Helpers for the JSON-lines stream ipatool writes to stdout with `--format json`.
enum IPAToolOutput {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParsing.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }()

    /// Splits output on newlines and carriage returns (progress bars use `\r`).
    static func lines(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func jsonObjects(in text: String) -> [[String: Any]] {
        lines(in: text).compactMap { line in
            guard line.hasPrefix("{"), let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    /// The final JSON object whose `level` is not `debug`, i.e. the command's result line.
    static func resultLine(in text: String) -> String? {
        let candidates = lines(in: text).filter { $0.hasPrefix("{") }
        for line in candidates.reversed() {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if let level = object["level"] as? String, level == "debug" { continue }
            if object["message"] != nil && object["success"] == nil && object["error"] == nil { continue }
            return line
        }
        return candidates.last
    }

    static func errorMessage(in text: String) -> String? {
        for object in jsonObjects(in: text).reversed() {
            if let error = object["error"] as? String, !error.isEmpty { return error }
            if let level = object["level"] as? String, level == "error", let message = object["message"] as? String {
                return message
            }
        }
        return nil
    }

    static func decodeResult<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let line = resultLine(in: text), let data = line.data(using: .utf8) else {
            throw EngineError(kind: .invalidResponse, rawMessage: "ipatool produced no JSON result")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw EngineError(kind: .invalidResponse, rawMessage: "Could not decode ipatool output: \(error.localizedDescription)")
        }
    }

    private static let percentRegex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#)

    /// Extracts a 0…1 fraction from a `schollz/progressbar` render line; nil when the line has no percentage.
    static func progressFraction(in line: String) -> Double? {
        guard let regex = percentRegex,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Int(line[range]), (0...100).contains(value) else { return nil }
        return Double(value) / 100
    }
}

enum DateParsing {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parse(_ string: String) -> Date? {
        (try? plain.parse(string)) ?? (try? fractional.parse(string))
    }
}
