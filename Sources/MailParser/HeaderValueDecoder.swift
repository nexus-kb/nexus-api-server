//
//  HeaderValueDecoder.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/12/26.
//

import Foundation

enum HeaderValueDecoder {
//    match RFC 2047 "encoded word" for non-ASCII text in email headers
//    =\?          literal =?
//    ([^?]+)      capture 1: character set, such as UTF-8
//    \?           literal ?
//    ([bBqQ])     capture 2: encoding, B/base64 or Q/quoted-printable-like
//    \?           literal ?
//    ([^?]*)      capture 3: encoded payload
//    \?=          literal ?=
    private static let encodedWordExpression =
        try! NSRegularExpression(
            pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
        )

    static func decodeEncodedWords(
        _ value: String
    ) -> String {
        let source = value as NSString
        let matches = encodedWordExpression.matches(
            in: value,
            range: NSRange(location: 0, length: source.length)
        )

//        skip decode if no matches
        guard !matches.isEmpty else {
            return value
        }

        var output = ""
        var previousEnd = 0
        var previousWasEncodedWord = false

//        Decode each RFC 2047 encoded-word match in source order
        for match in matches {
//            Extract everything between previous encoded word and current word
            let separatorRange = NSRange(
                location: previousEnd,
                length: match.range.location - previousEnd
            )
            let separator = source.substring(
                with: separatorRange
            )

            if !previousWasEncodedWord
                || !separator.allSatisfy(\.isWhitespace)
            {
                output += separator
            }

            let charset = source.substring(
                with: match.range(at: 1)
            )
            let encoding = source.substring(
                with: match.range(at: 2)
            )
            let payload = source.substring(
                with: match.range(at: 3)
            )

            if let decoded = decodeWord(
                charset: charset,
                encoding: encoding,
                payload: payload
            ) {
                output += decoded
            } else {
                output += source.substring(
                    with: match.range
                )
            }

            previousEnd = NSMaxRange(match.range)
            previousWasEncodedWord = true
        }

        if previousEnd < source.length {
            output += source.substring(
                from: previousEnd
            )
        }

        return output
    }

    static func decodeText(
        _ data: Data,
        charset: String?
    ) -> String {
        let normalized = charset?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        let encoding: String.Encoding

        switch normalized {
        case nil, "", "utf-8", "utf8", "us-ascii", "ascii":
            encoding = .utf8

        case "iso-8859-1", "latin1", "latin-1":
            encoding = .isoLatin1

        case "windows-1252", "cp1252":
            encoding = .windowsCP1252

        default:
            encoding = .utf8
        }

        if let value = String(
            data: data,
            encoding: encoding
        ) {
            return value
        }

        if let value = String(
            data: data,
            encoding: .utf8
        ) {
            return value
        }

        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeWord(
        charset: String,
        encoding: String,
        payload: String
    ) -> String? {
        let data: Data?

        if encoding.caseInsensitiveCompare("B")
            == .orderedSame
        {
            data = Data(
                base64Encoded: payload,
                options: .ignoreUnknownCharacters
            )
        } else {
            let normalized = payload.replacingOccurrences(
                of: "_",
                with: " "
            )

            data = decodeQuotedPrintable(
                Data(normalized.utf8),
                allowSoftLineBreaks: false
            )
        }

        guard let data else {
            return nil
        }

        return decodeText(
            data,
            charset: charset
        )
    }

    static func decodeQuotedPrintable(
        _ data: Data,
        allowSoftLineBreaks: Bool = true
    ) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var index = 0

        while index < bytes.count {
            guard bytes[index] == 61 else {
                output.append(bytes[index])
                index += 1
                continue
            }

            if allowSoftLineBreaks,
               index + 1 < bytes.count,
               bytes[index + 1] == 10
            {
                index += 2
                continue
            }

            if allowSoftLineBreaks,
               index + 2 < bytes.count,
               bytes[index + 1] == 13,
               bytes[index + 2] == 10
            {
                index += 3
                continue
            }

            if index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]),
               let low = hexValue(bytes[index + 2])
            {
                output.append((high << 4) | low)
                index += 3
                continue
            }

            output.append(bytes[index])
            index += 1
        }

        return Data(output)
    }

    private static func hexValue(
        _ byte: UInt8
    ) -> UInt8? {
        switch byte {
        case 48...57:
            byte - 48

        case 65...70:
            byte - 55

        case 97...102:
            byte - 87

        default:
            nil
        }
    }
}

struct HeaderParameterValue {
    let value: String
    let parameters: [String: String]
}

enum HeaderParameterParser {
    static func parse(
        _ rawValue: String?
    ) -> HeaderParameterValue {
        guard let rawValue else {
            return HeaderParameterValue(
                value: "",
                parameters: [:]
            )
        }

        let segments = splitSegments(rawValue)
        let value = segments.first?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased() ?? ""

        var parameters: [String: String] = [:]

        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(
                of: "="
            ) else {
                continue
            }

            let name = segment[..<equals]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

            var parameterValue = segment[
                segment.index(after: equals)...
            ].trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if parameterValue.count >= 2,
               parameterValue.first == "\"",
               parameterValue.last == "\""
            {
                parameterValue.removeFirst()
                parameterValue.removeLast()

                parameterValue = parameterValue
                    .replacingOccurrences(
                        of: "\\\"",
                        with: "\""
                    )
                    .replacingOccurrences(
                        of: "\\\\",
                        with: "\\"
                    )
            }

            parameters[name] = parameterValue
        }

        return HeaderParameterValue(
            value: value,
            parameters: parameters
        )
    }

    private static func splitSegments(
        _ value: String
    ) -> [String] {
        var segments: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\", isQuoted {
                current.append(character)
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }

            if character == ";", !isQuoted {
                segments.append(current)
                current = ""
                continue
            }

            current.append(character)
        }

        segments.append(current)
        return segments
    }
}
