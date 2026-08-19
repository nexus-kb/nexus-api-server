/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 */

import Foundation

/// Fixed parser for Content-Type and Content-Disposition field values,
/// including RFC 2231 extended parameters and continuations.
enum MIMEParameterParser {
    static func parse(_ source: String) -> ContentType? {
        let logical = logicalValue(source)
        let sections = splitSections(logical)
        guard let first = sections.first else {
            return nil
        }

        let media = stripComments(first)
        let slash = media.firstIndex(of: "/")
        let rawType = String(media[..<(slash ?? media.endIndex)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawType.isEmpty else {
            return nil
        }

        let rawSubtype: String?
        if let slash {
            let start = media.index(after: slash)
            let value = String(media[start...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rawSubtype = value.isEmpty ? nil : value.lowercased()
        } else {
            rawSubtype = nil
        }

        var attributes: [MIMEAttribute] = []
        var firstAttributeIndices: [String: Int] = [:]
        var continuations: [Continuation] = []

        func appendAttribute(_ attribute: MIMEAttribute) {
            let index = attributes.count
            attributes.append(attribute)
            if firstAttributeIndices[attribute.name] == nil {
                firstAttributeIndices[attribute.name] = index
            }
        }

        for section in sections.dropFirst() {
            guard let assignment = splitAssignment(stripComments(section)) else {
                continue
            }
            let rawName = assignment.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !rawName.isEmpty else {
                continue
            }

            let parsedName = parameterName(rawName)
            guard !parsedName.base.isEmpty else {
                continue
            }
            let unquoted = unquote(assignment.value)
            var value = unquoted.value
            guard !value.isEmpty else {
                continue
            }

            if parsedName.encoded {
                let extended = decodeExtendedValue(value)
                value = extended.value
                let languageName = parsedName.base + "-language"
                if let language = extended.language, !language.isEmpty,
                   firstAttributeIndices[languageName] == nil
                {
                    appendAttribute(
                        MIMEAttribute(
                            name: languageName,
                            value: language
                        )
                    )
                }
            } else {
                value = unquoted.wasQuoted
                    ? decodeWordsPreservingWhitespace(value)
                    : RFC2047Decoder.decodeWords(value)
            }
            value = value.replacingOccurrences(of: "\u{1F}", with: " ")

            if let position = parsedName.position, position > 0 {
                continuations.append(
                    Continuation(
                        name: parsedName.base,
                        position: position,
                        value: value
                    )
                )
            } else {
                appendAttribute(
                    MIMEAttribute(name: parsedName.base, value: value)
                )
            }
        }

        continuations.sort {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            if $0.position != $1.position {
                return $0.position < $1.position
            }
            return $0.value < $1.value
        }

        var continuationStart = 0
        while continuationStart < continuations.count {
            let name = continuations[continuationStart].name
            var continuationEnd = continuationStart + 1
            while continuationEnd < continuations.count,
                  continuations[continuationEnd].name == name
            {
                continuationEnd += 1
            }

            let attributeIndex = firstAttributeIndices[name]
            var fragments: [String] = []
            fragments.reserveCapacity(
                continuationEnd - continuationStart
                    + (attributeIndex == nil ? 0 : 1)
            )
            if let attributeIndex {
                fragments.append(attributes[attributeIndex].value)
            }
            for index in continuationStart..<continuationEnd {
                fragments.append(continuations[index].value)
            }
            let value = fragments.joined()

            if let attributeIndex {
                let old = attributes[attributeIndex]
                attributes[attributeIndex] = MIMEAttribute(
                    name: old.name,
                    value: value
                )
            } else {
                appendAttribute(
                    MIMEAttribute(
                        name: name,
                        value: value
                    )
                )
            }
            continuationStart = continuationEnd
        }

        return ContentType(
            type: rawType.lowercased(),
            subtype: rawSubtype,
            attributes: attributes
        )
    }

    private struct Continuation {
        let name: String
        let position: Int
        let value: String
    }

    private struct ParsedName {
        let base: String
        let position: Int?
        let encoded: Bool
    }

    private static func parameterName(_ name: String) -> ParsedName {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadLeadingStars = trimmedName.first == "*"
        let name = String(trimmedName.drop(while: { $0 == "*" }))

        guard let star = name.firstIndex(of: "*") else {
            return ParsedName(base: name, position: nil, encoded: false)
        }

        let base = String(name[..<star])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(name[name.index(after: star)...])
        if suffix.isEmpty {
            return ParsedName(base: base, position: 0, encoded: true)
        }

        if hadLeadingStars, suffix.first == "*" {
            return ParsedName(base: base, position: 0, encoded: true)
        }

        var digits = ""
        var encoded = false
        for character in suffix {
            if character.isNumber, !encoded {
                digits.append(character)
            } else if character == "*", !encoded {
                encoded = true
            } else {
                break
            }
        }

        if digits.isEmpty {
            // Be liberal with broken `name**=` spellings, as mail-parser is.
            return ParsedName(base: base, position: 0, encoded: true)
        }
        return ParsedName(
            base: base,
            position: Int(digits) ?? 0,
            encoded: encoded
        )
    }

    private static func decodeExtendedValue(
        _ source: String
    ) -> (value: String, language: String?) {
        var charset: String?
        var language: String?
        var payload = source

        if let first = source.firstIndex(of: "'") {
            charset = String(source[..<first])
            let afterFirst = source.index(after: first)
            if let second = source[afterFirst...].firstIndex(of: "'"),
               source[afterFirst..<second].allSatisfy({
                   $0.isLetter || $0.isNumber || $0 == "-"
               })
            {
                language = String(source[afterFirst..<second])
                payload = String(source[source.index(after: second)...])
            } else {
                payload = String(source[afterFirst...])
            }
        }

        let bytes = Data(payload.utf8)
        guard let decoded = TransferDecoder.decodePercentEncoded(bytes) else {
            return (source, language)
        }
        return (CharsetDecoder.decode(decoded, charset: charset), language)
    }

    private static func splitAssignment(
        _ section: String
    ) -> (name: String, value: String)? {
        var quoted = false
        var escaped = false
        for index in section.indices {
            let character = section[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == "=", !quoted {
                let valueStart = section.index(after: index)
                return (
                    String(section[..<index]),
                    String(section[valueStart...])
                )
            }
        }
        return nil
    }

    private static func unquote(
        _ source: String
    ) -> (value: String, wasQuoted: Bool) {
        let start = source.firstIndex(where: { !$0.isWhitespace })
            ?? source.endIndex
        guard start < source.endIndex, source[start] == "\"" else {
            return (
                source.trimmingCharacters(in: .whitespacesAndNewlines),
                false
            )
        }

        var output = ""
        var escaped = false
        var index = source.index(after: start)
        while index < source.endIndex {
            let character = source[index]
            if escaped {
                output.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                output.append(character)
            }
            index = source.index(after: index)
        }
        return (output, true)
    }

    private static func decodeWordsPreservingWhitespace(_ source: String) -> String {
        let bytes = Array(source.utf8)
        var output = ""
        var pending = 0
        var scan = 0
        var previousWasEncoded = false

        while scan + 1 < bytes.count {
            guard bytes[scan] == 0x3D,
                  bytes[scan + 1] == 0x3F,
                  let word = RFC2047Decoder.decodeWord(in: bytes, startingAt: scan)
            else {
                scan += 1
                continue
            }
            let separator = bytes[pending..<scan]
            if !previousWasEncoded || !separator.allSatisfy({ $0 == 0x1F }) {
                output += String(decoding: separator, as: UTF8.self)
                    .replacingOccurrences(of: "\u{1F}", with: " ")
            }
            output += word.value
            scan += word.consumedByteCount
            pending = scan
            previousWasEncoded = true
        }
        if pending < bytes.count {
            output += String(decoding: bytes[pending...], as: UTF8.self)
                .replacingOccurrences(of: "\u{1F}", with: " ")
        }
        return output
    }

    private static func splitSections(_ source: String) -> [String] {
        var sections: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        var commentDepth = 0

        for character in source {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", quoted {
                current.append(character)
                escaped = true
            } else if character == "\"", commentDepth == 0 {
                current.append(character)
                quoted.toggle()
            } else if character == "(", !quoted {
                commentDepth += 1
                current.append(character)
            } else if character == ")", !quoted, commentDepth > 0 {
                commentDepth -= 1
                current.append(character)
            } else if character == ";", !quoted, commentDepth == 0 {
                sections.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        sections.append(current)
        return sections
    }

    private static func stripComments(_ source: String) -> String {
        var output = ""
        var depth = 0
        var quoted = false
        var escaped = false

        for character in source {
            if escaped {
                if depth == 0 {
                    output.append(character)
                }
                escaped = false
                continue
            }
            if character == "\\" {
                if depth == 0 {
                    output.append(character)
                }
                escaped = true
            } else if character == "\"", depth == 0 {
                quoted.toggle()
                output.append(character)
            } else if character == "(", !quoted {
                depth += 1
            } else if character == ")", !quoted, depth > 0 {
                depth -= 1
            } else if depth == 0 {
                output.append(character)
            }
        }
        return output
    }

    private static func logicalValue(_ source: String) -> String {
        let source = source.replacingOccurrences(of: "\r\n", with: "\n")
        var output = ""
        var hasNonWhitespace = false
        var quoted = false
        var escaped = false
        var index = source.startIndex

        func appendToOutput(_ character: Character) {
            output.append(character)
            if !character.isWhitespace {
                hasNonWhitespace = true
            }
        }

        while index < source.endIndex {
            let character = source[index]
            if escaped {
                appendToOutput(character)
                escaped = false
                index = source.index(after: index)
                continue
            }
            if character == "\\", quoted {
                appendToOutput(character)
                escaped = true
                index = source.index(after: index)
                continue
            }
            if character == "\"" {
                quoted.toggle()
                appendToOutput(character)
                index = source.index(after: index)
                continue
            }

            if character == "\r" || character == "\n" {
                var next = source.index(after: index)
                guard next < source.endIndex,
                      source[next] == " " || source[next] == "\t"
                else {
                    break
                }

                if quoted {
                    // Preserve all folding whitespace inside a quoted string.
                    while next < source.endIndex,
                          source[next] == " " || source[next] == "\t"
                    {
                        appendToOutput("\u{1F}")
                        next = source.index(after: next)
                    }
                } else if hasNonWhitespace, output.last != ";"
                {
                    appendToOutput(";")
                    while next < source.endIndex,
                          source[next] == " " || source[next] == "\t"
                    {
                        next = source.index(after: next)
                    }
                } else {
                    while next < source.endIndex,
                          source[next] == " " || source[next] == "\t"
                    {
                        next = source.index(after: next)
                    }
                }
                index = next
                continue
            }

            appendToOutput(character)
            index = source.index(after: index)
        }
        return output
    }
}
