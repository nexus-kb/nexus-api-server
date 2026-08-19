/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 */

import Foundation

/// Best-effort structured parser for Received trace fields.
enum ReceivedParser {
    static func parse(_ source: String) -> Received? {
        let value = logicalValue(source)
        let (_, dateText) = splitDate(value)
        let tokens = tokenize(value)

        var from: Host?
        var fromIP: String?
        var fromIPReverse: String?
        var by: Host?
        var forRecipient: String?
        var protocolValue: MailProtocol?
        var tlsVersion: TLSVersion?
        var tlsCipher: String?
        var identifier: String?
        var ident: String?
        var helo: Host?
        var heloCommand: Greeting?
        var via: String?

        var state = State.none
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.text.lowercased()

            if lower == "from", from == nil {
                if let next = nextValue(after: index, in: tokens, skipping: [.openBracket]) {
                    from = host(next.token.text)
                    index = next.index
                }
                state = .from
            } else if lower == "by", token.commentDepth == 0 {
                if let next = nextValue(
                    after: index,
                    in: tokens,
                    skipping: [.openBracket, .openAngle]
                ) {
                    by = host(next.token.text)
                    index = next.index
                }
                state = .by
            } else if lower == "for", token.commentDepth == 0 {
                if let next = nextValue(
                    after: index,
                    in: tokens,
                    skipping: [.equal, .openAngle]
                ), isEmailToken(next.token.text)
                {
                    forRecipient = next.token.text
                    index = next.index
                }
                state = .forRecipient
            } else if lower == "id", token.commentDepth == 0 {
                if let next = nextValue(
                    after: index,
                    in: tokens,
                    skipping: [.equal, .openAngle, .openBracket, .colon]
                ) {
                    identifier = next.token.text
                        .split(separator: ":", maxSplits: 1)
                        .first.map(String.init)
                    index = next.index
                }
                state = .id
            } else if lower == "with", token.commentDepth == 0 {
                var scan = index + 1
                while scan < tokens.count {
                    let candidate = tokens[scan]
                    if let parsed = mailProtocol(candidate.text) {
                        protocolValue = parsed
                        index = scan
                        break
                    }
                    let keyword = candidate.text.lowercased()
                    if candidate.commentDepth == 0,
                       ["by", "for", "from", "id", "via", "with"].contains(keyword)
                    {
                        break
                    }
                    scan += 1
                }
                state = .with
            } else if lower == "via", token.commentDepth == 0 {
                if let next = nextValue(after: index, in: tokens, skipping: [.equal]) {
                    via = next.token.text
                    index = next.index
                }
                state = .via
            } else if lower == "ident", token.commentDepth > 0 {
                if let next = nextValue(
                    after: index,
                    in: tokens,
                    skipping: [.equal, .openAngle, .openBracket, .colon]
                ) {
                    ident = next.token.text
                    index = next.index
                }
            } else if let greeting = greeting(lower),
                      state == .from,
                      token.commentDepth > 0
            {
                heloCommand = greeting
                if let next = nextValue(
                    after: index,
                    in: tokens,
                    skipping: [.equal, .openBracket, .colon]
                ) {
                    helo = host(next.token.text)
                    index = next.index
                }
            } else if let ip = normalizedIPAddress(token.text),
                      state == .from,
                      token.bracketDepth > 0
                        || (token.commentDepth > 0 && fromIP == nil)
            {
                fromIP = ip
            } else if state == .from,
                      token.commentDepth > 0,
                      fromIPReverse == nil,
                      isDomain(token.text)
            {
                fromIPReverse = token.text
            } else if state == .from, isEmailToken(token.text) {
                var value = token.text
                if value.lowercased().hasPrefix("ident:") {
                    value.removeFirst(6)
                }
                ident = value.hasSuffix("@")
                    ? String(value.dropLast())
                    : value
            }

            if tlsVersion == nil, token.commentDepth > 0,
               let parsed = parseTLSVersion(token.text)
            {
                tlsVersion = parsed
            }
            if (token.commentDepth > 0 || tlsCipher == nil),
               let cipher = cipherName(token.text)
            {
                tlsCipher = cipher
            }

            index += 1
        }

        let date = dateText.flatMap(parseReceivedDate)
        guard from != nil
            || fromIP != nil
            || fromIPReverse != nil
            || by != nil
            || forRecipient != nil
            || protocolValue != nil
            || tlsVersion != nil
            || tlsCipher != nil
            || identifier != nil
            || ident != nil
            || helo != nil
            || heloCommand != nil
            || via != nil
            || date != nil
        else {
            return nil
        }

        return Received(
            from: from,
            fromIP: fromIP,
            fromIPReverse: fromIPReverse,
            by: by,
            forRecipient: forRecipient,
            protocolValue: protocolValue,
            tlsVersion: tlsVersion,
            tlsCipher: tlsCipher,
            id: identifier,
            ident: ident,
            helo: helo,
            heloCommand: heloCommand,
            via: via,
            date: date
        )
    }

    private enum State {
        case from
        case by
        case forRecipient
        case id
        case with
        case via
        case none
    }

    private enum TokenKind: Hashable {
        case word
        case openBracket
        case closeBracket
        case openAngle
        case closeAngle
        case openParenthesis
        case closeParenthesis
        case equal
        case colon
        case slash
        case quote
        case comma
        case semicolon
    }

    private struct Token {
        let kind: TokenKind
        let text: String
        let commentDepth: Int
        let bracketDepth: Int
    }

    private static func tokenize(_ source: String) -> [Token] {
        var result: [Token] = []
        var word = ""
        var commentDepth = 0
        var bracketDepth = 0
        var wordCommentDepth = 0
        var wordBracketDepth = 0

        func punctuation(_ character: Character) -> TokenKind? {
            switch character {
            case "[": .openBracket
            case "]": .closeBracket
            case "<": .openAngle
            case ">": .closeAngle
            case "(": .openParenthesis
            case ")": .closeParenthesis
            case "=": .equal
            case "/": .slash
            case "\"": .quote
            case ",": .comma
            case ";": .semicolon
            default: nil
            }
        }

        func appendWord(_ value: String) {
            guard !value.isEmpty else {
                return
            }

            if value.count > 5,
               value.prefix(5).caseInsensitiveCompare("ipv6:") == .orderedSame
            {
                result.append(
                    Token(
                        kind: .word,
                        text: String(value.prefix(4)),
                        commentDepth: wordCommentDepth,
                        bracketDepth: wordBracketDepth
                    )
                )
                result.append(
                    Token(
                        kind: .colon,
                        text: ":",
                        commentDepth: wordCommentDepth,
                        bracketDepth: wordBracketDepth
                    )
                )
                appendWord(String(value.dropFirst(5)))
                return
            }

            let colonCount = value.reduce(into: 0) { count, character in
                if character == ":" {
                    count += 1
                }
            }
            let prefix = value.prefix { $0 != ":" }
            let isIPAddressCandidate = colonCount >= 2
                && prefix.utf8.allSatisfy {
                    (0x30...0x39).contains($0)
                        || (0x41...0x46).contains($0)
                        || (0x61...0x66).contains($0)
                }
            if isIPAddressCandidate {
                result.append(
                    Token(
                        kind: .word,
                        text: value,
                        commentDepth: wordCommentDepth,
                        bracketDepth: wordBracketDepth
                    )
                )
                return
            }

            var start = value.startIndex
            for index in value.indices where value[index] == ":" {
                if start < index {
                    result.append(
                        Token(
                            kind: .word,
                            text: String(value[start..<index]),
                            commentDepth: wordCommentDepth,
                            bracketDepth: wordBracketDepth
                        )
                    )
                }
                result.append(
                    Token(
                        kind: .colon,
                        text: ":",
                        commentDepth: wordCommentDepth,
                        bracketDepth: wordBracketDepth
                    )
                )
                start = value.index(after: index)
            }
            if start < value.endIndex {
                result.append(
                    Token(
                        kind: .word,
                        text: String(value[start...]),
                        commentDepth: wordCommentDepth,
                        bracketDepth: wordBracketDepth
                    )
                )
            }
        }

        func flush() {
            guard !word.isEmpty else {
                return
            }
            appendWord(word)
            word = ""
        }

        for character in source {
            if character.isWhitespace {
                flush()
                continue
            }

            if let kind = punctuation(character) {
                flush()
                result.append(
                    Token(
                        kind: kind,
                        text: String(character),
                        commentDepth: commentDepth,
                        bracketDepth: bracketDepth
                    )
                )
                if character == "(" {
                    commentDepth += 1
                } else if character == ")" {
                    commentDepth = max(0, commentDepth - 1)
                } else if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                }
                continue
            }

            if word.isEmpty {
                wordCommentDepth = commentDepth
                wordBracketDepth = bracketDepth
            }
            word.append(character)
        }
        flush()

        return result
    }

    private static func nextValue(
        after index: Int,
        in tokens: [Token],
        skipping kinds: Set<TokenKind>
    ) -> (index: Int, token: Token)? {
        var next = index + 1
        while next < tokens.count {
            let token = tokens[next]
            if kinds.contains(token.kind) {
                next += 1
                continue
            }
            guard token.kind == .word else {
                return nil
            }
            return (next, token)
        }
        return nil
    }

    private static func host(_ source: String) -> Host {
        if let ip = normalizedIPAddress(source) {
            return .ipAddress(ip)
        }
        return .name(source)
    }

    private static func normalizedIPAddress(_ source: String) -> String? {
        if let octets = parseIPv4(source) {
            return octets.map(String.init).joined(separator: ".")
        }
        guard let groups = parseIPv6(source) else {
            return nil
        }
        return formatIPv6(groups)
    }

    private static func parseIPv4(_ source: String) -> [UInt8]? {
        let components = source.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count == 4 else {
            return nil
        }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for component in components {
            guard !component.isEmpty,
                  component.count <= 3,
                  component.count == 1 || component.first != "0",
                  component.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  let value = UInt8(component)
            else {
                return nil
            }
            octets.append(value)
        }
        return octets
    }

    private static func parseIPv6(_ source: String) -> [UInt16]? {
        guard source.contains(":"), !source.contains("%") else {
            return nil
        }

        let compression = source.range(of: "::")
        if let compression,
           source[compression.upperBound...].range(of: "::") != nil
        {
            return nil
        }

        let leftText: Substring
        let rightText: Substring
        if let compression {
            leftText = source[..<compression.lowerBound]
            rightText = source[compression.upperBound...]
        } else {
            leftText = source[...]
            rightText = ""
        }

        func components(_ value: Substring) -> [Substring]? {
            guard !value.isEmpty else {
                return []
            }
            let result = value.split(
                separator: ":",
                omittingEmptySubsequences: false
            )
            return result.contains(where: \.isEmpty) ? nil : result
        }

        guard let left = components(leftText),
              let right = components(rightText)
        else {
            return nil
        }

        let allComponents = left + right
        var groups: [UInt16] = []
        groups.reserveCapacity(8)
        for (index, component) in allComponents.enumerated() {
            if component.contains(".") {
                guard index == allComponents.count - 1,
                      let octets = parseIPv4(String(component))
                else {
                    return nil
                }
                groups.append(UInt16(octets[0]) << 8 | UInt16(octets[1]))
                groups.append(UInt16(octets[2]) << 8 | UInt16(octets[3]))
            } else {
                guard !component.isEmpty,
                      component.count <= 4,
                      component.utf8.allSatisfy({
                          (0x30...0x39).contains($0)
                              || (0x41...0x46).contains($0)
                              || (0x61...0x66).contains($0)
                      }),
                      let value = UInt16(component, radix: 16)
                else {
                    return nil
                }
                groups.append(value)
            }
        }

        if compression != nil {
            guard groups.count < 8 else {
                return nil
            }
            groups.insert(
                contentsOf: repeatElement(0, count: 8 - groups.count),
                at: left.reduce(0) { count, component in
                    count + (component.contains(".") ? 2 : 1)
                }
            )
        } else if groups.count != 8 {
            return nil
        }

        return groups.count == 8 ? groups : nil
    }

    private static func formatIPv6(_ groups: [UInt16]) -> String {
        if groups[0...4].allSatisfy({ $0 == 0 }), groups[5] == 0xFFFF {
            let octets = [
                UInt8(groups[6] >> 8),
                UInt8(truncatingIfNeeded: groups[6]),
                UInt8(groups[7] >> 8),
                UInt8(truncatingIfNeeded: groups[7]),
            ]
            return "::ffff:" + octets.map(String.init).joined(separator: ".")
        }

        var bestStart: Int?
        var bestCount = 0
        var index = 0
        while index < groups.count {
            guard groups[index] == 0 else {
                index += 1
                continue
            }
            let start = index
            while index < groups.count, groups[index] == 0 {
                index += 1
            }
            let count = index - start
            if count >= 2, count > bestCount {
                bestStart = start
                bestCount = count
            }
        }

        let values = groups.map { String($0, radix: 16) }
        guard let bestStart else {
            return values.joined(separator: ":")
        }
        let left = values[..<bestStart].joined(separator: ":")
        let right = values[(bestStart + bestCount)...].joined(separator: ":")
        if left.isEmpty {
            return right.isEmpty ? "::" : "::" + right
        }
        return right.isEmpty ? left + "::" : left + "::" + right
    }

    private static func isDomain(_ source: String) -> Bool {
        var hasASCIILetter = false
        var hasDot = false
        for byte in source.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A:
                hasASCIILetter = true
            case 0x30...0x39, 0x2D:
                break
            case 0x2E:
                hasDot = true
            case 0x7F...0xFF:
                break
            default:
                return false
            }
        }
        return hasASCIILetter && hasDot
    }

    private static func isEmailToken(_ source: String) -> Bool {
        var atCount = 0
        var hasASCIILetter = false
        for byte in source.utf8 {
            if byte == 0x40 {
                atCount += 1
            } else if (0x41...0x5A).contains(byte)
                || (0x61...0x7A).contains(byte)
            {
                hasASCIILetter = true
            }
        }
        return atCount == 1 && hasASCIILetter
    }

    private static func mailProtocol(_ source: String) -> MailProtocol? {
        let value = source.lowercased()
        return switch value {
        case "smtp", "smtpd", "smtpsvc", "smtps", "bsmtp", "local-bsmtp": .smtp
        case "esmtp", "local-esmtp": .esmtp
        case "esmtpa": .esmtpa
        case "esmtps", "esmtp-tls", "local-esmtps": .esmtps
        case "esmtpsa": .esmtpsa
        case "lmtp", "slmtp": .lmtp
        case "lmtpa": .lmtpa
        case "lmtps": .lmtps
        case "lmtpsa": .lmtpsa
        case "mms": .mms
        case "utf8smtp": .utf8smtp
        case "utf8smtpa": .utf8smtpa
        case "utf8smtps": .utf8smtps
        case "utf8smtpsa": .utf8smtpsa
        case "utf8lmtp": .utf8lmtp
        case "utf8lmtpa": .utf8lmtpa
        case "utf8lmtps": .utf8lmtps
        case "utf8lmtpsa": .utf8lmtpsa
        case "http", "httprest", "httpu": .http
        case "https": .https
        case "imap": .imap
        case "pop3": .pop3
        case "local", "socket", "stdin": .local
        default: nil
        }
    }

    private static func greeting(_ source: String) -> Greeting? {
        return switch source {
        case "helo": .helo
        case "ehlo": .ehlo
        case "lhlo": .lhlo
        default: nil
        }
    }

    private static func parseTLSVersion(_ source: String) -> TLSVersion? {
        let value = source.lowercased()
        guard value.utf8.allSatisfy({ byte in
            (0x61...0x7A).contains(byte)
                || (0x30...0x39).contains(byte)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F
        }) else {
            return nil
        }

        let fingerprint = String(
            decoding: value.utf8.filter {
                (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
            },
            as: UTF8.self
        )
        switch fingerprint {
        case "ssl2" where value == fingerprint,
             "sslv2" where value == fingerprint:
            return .ssl2
        case "ssl3" where value == fingerprint,
             "sslv3" where value == fingerprint:
            return .ssl3
        case "tls1" where value == fingerprint,
             "tlsv1" where value == fingerprint:
            return .tls1_0
        case "tls10":
            return .tls1_0
        case "tlsv10" where !value.contains("-"):
            return .tls1_0
        case "tls11":
            return .tls1_1
        case "tlsv11" where !value.contains("-"):
            return .tls1_1
        case "tls12":
            return .tls1_2
        case "tlsv12" where !value.contains("-"):
            return .tls1_2
        case "tls13":
            return .tls1_3
        case "tlsv13" where !value.contains("-"):
            return .tls1_3
        case "dtls10" where !value.contains("-"),
             "dtlsv10" where !value.contains("-"):
            return .dtls1_0
        case "dtls12" where !value.contains("-"),
             "dtlsv12" where !value.contains("-"):
            return .dtls1_2
        case "dtls13" where !value.contains("-"),
             "dtlsv13" where !value.contains("-"):
            return .dtls1_3
        default:
            return nil
        }
    }

    private static func cipherName(_ source: String) -> String? {
        for component in source.split(separator: ":") {
            let candidate = String(component)
            guard parseTLSVersion(candidate) == nil,
                  !candidate.contains("."),
                  candidate.count > 6,
                  candidate.contains(where: \.isNumber),
                  candidate.contains("_") || candidate.contains("-"),
                  candidate.allSatisfy({
                      !$0.isLetter || $0.isUppercase
                  })
            else {
                continue
            }

            let lower = candidate.lowercased()
            let prefixes = [
                "rsa", "ecd", "dce", "dhe", "psk", "prp", "aes", "des", "tls",
            ]
            if prefixes.contains(where: lower.hasPrefix) {
                return candidate
            }
        }
        return nil
    }

    private static func parseReceivedDate(_ source: String) -> MailDateTime? {
        let months: [String: Int] = [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
            "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        ]
        var values: [Int] = []
        var token = ""

        func flush() {
            guard !token.isEmpty else { return }
            let lower = token.lowercased()
            if let month = months[lower] {
                values.append(month)
            } else if let number = Int(token) {
                values.append(number)
            }
            token = ""
        }

        for character in source {
            if character.isNumber || character.isLetter || character == "."
                || ((character == "+" || character == "-") && token.isEmpty)
            {
                token.append(character)
            } else if character == ":" || character == "," || character.isWhitespace {
                flush()
            }
        }
        flush()

        guard values.count >= 6 else {
            return nil
        }
        let zone = values.count > 6 ? values[6] : 0
        let positive = values.count > 6 ? zone >= 0 : false
        // Preserve mail-parser's release-mode wrapping conversion for i64::MIN
        // without calling abs(Int.min), which traps in Swift debug builds.
        let absoluteZone = zone == .min ? zone : Swift.abs(zone)
        let rawYear = values[2]

        return MailDateTime(
            year: (1...99).contains(rawYear) ? rawYear + 1900 : rawYear & 0xFFFF,
            month: values[1] & 0xFF,
            day: values[0] & 0xFF,
            hour: values[3] & 0xFF,
            minute: values[4] & 0xFF,
            second: values[5] & 0xFF,
            isNegativeOffset: !positive,
            offsetHour: (absoluteZone / 100) & 0xFF,
            offsetMinute: (absoluteZone % 100) & 0xFF
        )
    }

    private static func splitDate(_ source: String) -> (String, String?) {
        var commentDepth = 0
        var quoted = false
        var escaped = false
        for index in source.indices {
            let character = source[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"", commentDepth == 0 {
                quoted.toggle()
            } else if character == "(", !quoted {
                commentDepth += 1
            } else if character == ")", !quoted {
                commentDepth = max(0, commentDepth - 1)
            } else if character == ";", !quoted, commentDepth == 0 {
                let dateStart = source.index(after: index)
                return (String(source[..<index]), String(source[dateStart...]))
            }
        }
        return (source, nil)
    }

    private static func logicalValue(_ source: String) -> String {
        let source = source.replacingOccurrences(of: "\r\n", with: "\n")
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character == "\r" || character == "\n" {
                var next = source.index(after: index)
                guard next < source.endIndex,
                      source[next] == " " || source[next] == "\t"
                else {
                    break
                }
                output.append(" ")
                while next < source.endIndex,
                      source[next] == " " || source[next] == "\t"
                {
                    next = source.index(after: next)
                }
                index = next
                continue
            }
            output.append(character)
            index = source.index(after: index)
        }
        return output
    }
}
