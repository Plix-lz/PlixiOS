import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    /// Igual que org.json `optString`: valores nulos o "null" cuentan como vacío.
    func str(_ key: String) -> String {
        guard let value = self[key], !(value is NSNull) else { return "" }
        if let text = value as? String { return text == "null" ? "" : text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        if let number = self[key] as? NSNumber { return number.intValue }
        if let text = self[key] as? String, let value = Int(text.trimmingCharacters(in: .whitespaces)) { return value }
        return fallback
    }

    func int64(_ key: String, _ fallback: Int64 = 0) -> Int64 {
        if let number = self[key] as? NSNumber { return number.int64Value }
        if let text = self[key] as? String, let value = Int64(text.trimmingCharacters(in: .whitespaces)) { return value }
        return fallback
    }

    func double(_ key: String, _ fallback: Double = 0) -> Double {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let text = self[key] as? String, let value = Double(text) { return value }
        return fallback
    }

    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        if let number = self[key] as? NSNumber { return number.boolValue }
        if let text = self[key] as? String { return text == "true" }
        return fallback
    }

    func obj(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func arr(_ key: String) -> [Any]? { self[key] as? [Any] }
    func objects(_ key: String) -> [JSONObject] { (self[key] as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }
}

enum JSONUtil {
    static func object(from data: Data) throws -> JSONObject {
        guard let value = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw PlixError.invalidResponse
        }
        return value
    }

    static func object(from text: String) -> JSONObject? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
    }

    static func array(from text: String) -> [Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    }

    static func string(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

enum PlixError: LocalizedError {
    case invalidResponse
    case http(Int)
    case missingApiKey
    case firebaseUnavailable
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Respuesta inválida del servidor."
        case .http(let code): return "El servidor respondió con el código \(code)."
        case .missingApiKey: return "Falta la clave de TMDB en Secrets.xcconfig."
        case .firebaseUnavailable: return "Las funciones en la nube no están configuradas (falta GoogleService-Info.plist)."
        case .message(let text): return text
        }
    }
}

/// JSON que conserva el orden de las claves de los objetos.
/// El orden de servidores y plataformas depende del orden del JSON remoto (org.json lo conserva,
/// JSONSerialization no).
indirect enum OrderedJSON {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var entries: [(String, OrderedJSON)] {
        if case .object(let pairs) = self { return pairs }
        return []
    }

    var items: [OrderedJSON] {
        if case .array(let values) = self { return values }
        return []
    }

    var stringValue: String? {
        switch self {
        case .string(let text): return text
        case .number(let number):
            return number.rounded() == number ? String(Int64(number)) : String(number)
        default: return nil
        }
    }

    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }

    subscript(key: String) -> OrderedJSON? {
        entries.first(where: { $0.0 == key })?.1
    }

    func string(_ key: String) -> String {
        guard let value = self[key], let text = value.stringValue, text != "null" else { return "" }
        return text
    }

    func bool(_ key: String) -> Bool {
        if case .bool(let flag)? = self[key] { return flag }
        return false
    }

    static func parse(_ data: Data) -> OrderedJSON? {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        guard let value = parser.parseValue() else { return nil }
        return value
    }

    static func parse(_ text: String) -> OrderedJSON? {
        guard let data = text.data(using: .utf8) else { return nil }
        return parse(data)
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func parseValue() -> OrderedJSON? {
            skipWhitespace()
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case UInt8(ascii: "{"): return parseObject()
            case UInt8(ascii: "["): return parseArray()
            case UInt8(ascii: "\""): return parseString().map { .string($0) }
            case UInt8(ascii: "t"): return consume("true") ? .bool(true) : nil
            case UInt8(ascii: "f"): return consume("false") ? .bool(false) : nil
            case UInt8(ascii: "n"): return consume("null") ? .null : nil
            default: return parseNumber()
            }
        }

        mutating func consume(_ word: String) -> Bool {
            let wordBytes = Array(word.utf8)
            guard index + wordBytes.count <= bytes.count,
                  Array(bytes[index..<(index + wordBytes.count)]) == wordBytes else { return false }
            index += wordBytes.count
            return true
        }

        mutating func parseObject() -> OrderedJSON? {
            index += 1
            var pairs: [(String, OrderedJSON)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while index < bytes.count {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = parseString() else { return nil }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
                index += 1
                guard let value = parseValue() else { return nil }
                if let existing = pairs.firstIndex(where: { $0.0 == key }) {
                    pairs[existing].1 = value
                } else {
                    pairs.append((key, value))
                }
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                return nil
            }
            return nil
        }

        mutating func parseArray() -> OrderedJSON? {
            index += 1
            var values: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
            while index < bytes.count {
                guard let value = parseValue() else { return nil }
                values.append(value)
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
                return nil
            }
            return nil
        }

        mutating func parseString() -> String? {
            index += 1
            var buffer: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    return String(decoding: buffer, as: UTF8.self)
                }
                if byte == UInt8(ascii: "\\") {
                    index += 1
                    guard index < bytes.count else { return nil }
                    let escaped = bytes[index]
                    switch escaped {
                    case UInt8(ascii: "n"): buffer.append(0x0A)
                    case UInt8(ascii: "t"): buffer.append(0x09)
                    case UInt8(ascii: "r"): buffer.append(0x0D)
                    case UInt8(ascii: "b"): buffer.append(0x08)
                    case UInt8(ascii: "f"): buffer.append(0x0C)
                    case UInt8(ascii: "u"):
                        guard let scalarValue = parseHex4() else { return nil }
                        var code = scalarValue
                        if (0xD800...0xDBFF).contains(code),
                           index + 2 < bytes.count,
                           bytes[index + 1] == UInt8(ascii: "\\"),
                           bytes[index + 2] == UInt8(ascii: "u") {
                            index += 2
                            if let low = parseHex4(), (0xDC00...0xDFFF).contains(low) {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            }
                        }
                        let scalar: Unicode.Scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                        buffer.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default: buffer.append(escaped)
                    }
                    index += 1
                    continue
                }
                buffer.append(byte)
                index += 1
            }
            return nil
        }

        /// Lee 4 dígitos hex tras "\u"; deja el índice en el último dígito.
        mutating func parseHex4() -> UInt32? {
            guard index + 4 < bytes.count else { return nil }
            let hex = String(decoding: bytes[(index + 1)...(index + 4)], as: UTF8.self)
            guard let value = UInt32(hex, radix: 16) else { return nil }
            index += 4
            return value
        }

        mutating func parseNumber() -> OrderedJSON? {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                let isNumberByte = (byte >= 0x30 && byte <= 0x39) || byte == UInt8(ascii: "-")
                    || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
                    || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")
                if !isNumberByte { break }
                index += 1
            }
            guard index > start, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { return nil }
            return .number(value)
        }
    }
}
