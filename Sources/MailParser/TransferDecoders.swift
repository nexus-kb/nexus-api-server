/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 * Base64, quoted-printable, percent, and RFC 2047 decoding behavior is
 * substantially derived from mail-parser 0.11.6.
 */

import Foundation

/// Fixed transfer decoders used by the RFC 5322 and MIME parser.
enum TransferDecoder {
    /// Decodes mail-parser's permissive MIME Base64 dialect.
    ///
    /// ASCII whitespace and redundant padding are accepted. Any other
    /// non-alphabet byte makes the transfer invalid. As in mail-parser,
    /// an unterminated final quantum is not emitted.
    static func decodeBase64(_ data: Data) -> Data? {
        return decodeBase64(data, stopAtEncodedWordTerminator: false)?.data
    }

    static func decodeBase64<C: Collection>(_ bytes: C) -> Data?
    where C.Element == UInt8 {
        decodeBase64(Data(bytes))
    }

    /// MIME-body spelling retained to make transfer dispatch self-documenting.
    static func decodeBase64MIME(_ data: Data) -> Data? {
        decodeBase64(data)
    }

    /// Strict quoted-printable decoder used outside MIME body recovery.
    /// This matches `quoted_printable_decode` in mail-parser.
    static func decodeQuotedPrintable(_ data: Data) -> Data? {
        var output: [UInt8] = []
        output.reserveCapacity(data.count)

        var state = QuotedPrintableState.none
        var highNibble: UInt8 = 0
        var trailingWhitespace = 0
        var lineEnding: [UInt8] = [0x0A]

        for byte in data {
            switch byte {
            case asciiEquals:
                guard state == .none else { return nil }
                state = .equals

            case asciiLF:
                if state == .equals {
                    state = .none
                } else {
                    if trailingWhitespace > 0 {
                        output.removeLast(min(trailingWhitespace, output.count))
                    }
                    output.append(contentsOf: lineEnding)
                }
                trailingWhitespace = 0

            case asciiCR:
                lineEnding = [asciiCR, asciiLF]

            default:
                switch state {
                case .none:
                    if byte.isASCIIWhitespace {
                        trailingWhitespace += 1
                    } else {
                        trailingWhitespace = 0
                    }
                    output.append(byte)

                case .equals:
                    if let nibble = hexValue(byte) {
                        highNibble = nibble
                        state = .firstHexDigit
                    } else if !byte.isASCIIWhitespace {
                        return nil
                    }

                case .firstHexDigit:
                    guard let lowNibble = hexValue(byte) else { return nil }
                    output.append((highNibble << 4) | lowNibble)
                    trailingWhitespace = 0
                    state = .none
                }
            }
        }

        return Data(output)
    }

    /// Tolerant MIME quoted-printable decoding.
    ///
    /// Invalid hex escapes are retained verbatim, matching the recovery path
    /// used by mail-parser's MIME stream decoder. A repeated `=` while an
    /// escape is pending is the one malformed form that fails the transfer.
    static func decodeQuotedPrintableMIME(_ data: Data) -> Data? {
        var output: [UInt8] = []
        output.reserveCapacity(data.count)

        var state = QuotedPrintableState.none
        var highNibble: UInt8 = 0
        var highNibbleByte: UInt8 = 0
        var trailingWhitespace = 0
        var lineEnding: [UInt8] = [asciiLF]

        for byte in data {
            switch byte {
            case asciiEquals:
                guard state == .none else { return nil }
                state = .equals

            case asciiLF:
                if state == .equals {
                    state = .none
                } else {
                    if trailingWhitespace > 0 {
                        output.removeLast(min(trailingWhitespace, output.count))
                    }
                    output.append(contentsOf: lineEnding)
                }
                trailingWhitespace = 0

            case asciiCR:
                lineEnding = [asciiCR, asciiLF]

            default:
                switch state {
                case .none:
                    if byte.isASCIIWhitespace {
                        trailingWhitespace += 1
                    } else {
                        trailingWhitespace = 0
                    }
                    output.append(byte)

                case .equals:
                    if let nibble = hexValue(byte) {
                        highNibble = nibble
                        highNibbleByte = byte
                        state = .firstHexDigit
                    } else if !byte.isASCIIWhitespace {
                        output.append(asciiEquals)
                        output.append(byte)
                        trailingWhitespace = 0
                        state = .none
                    }

                case .firstHexDigit:
                    if let lowNibble = hexValue(byte) {
                        output.append((highNibble << 4) | lowNibble)
                    } else {
                        output.append(asciiEquals)
                        output.append(highNibbleByte)
                        output.append(byte)
                    }
                    trailingWhitespace = 0
                    state = .none
                }
            }
        }

        return Data(output)
    }

    /// Decodes RFC 2047 Q payload bytes. The input excludes the terminating
    /// `?=` sequence.
    static func decodeQuotedPrintableWord(_ data: Data) -> Data? {
        var output: [UInt8] = []
        output.reserveCapacity(data.count)

        var state = QuotedPrintableState.none
        var highNibble: UInt8 = 0

        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            data.formIndex(after: &index)

            switch byte {
            case asciiEquals:
                guard state == .none else { return nil }
                state = .equals

            case asciiLF:
                guard index < data.endIndex,
                      data[index] == asciiSpace || data[index] == asciiTab
                else { return nil }
                while index < data.endIndex,
                      data[index] == asciiSpace || data[index] == asciiTab {
                    data.formIndex(after: &index)
                }

            case asciiUnderscore:
                output.append(asciiSpace)

            case asciiQuestion:
                // The stream decoder treats a lone `?` as literal data even
                // while an escape is pending. The terminating `?=` has already
                // been removed by the encoded-word scanner.
                output.append(asciiQuestion)

            case asciiCR:
                break

            default:
                switch state {
                case .none:
                    output.append(byte)
                case .equals:
                    guard let nibble = hexValue(byte) else { return nil }
                    highNibble = nibble
                    state = .firstHexDigit
                case .firstHexDigit:
                    guard let lowNibble = hexValue(byte) else { return nil }
                    output.append((highNibble << 4) | lowNibble)
                    state = .none
                }
            }
        }

        // mail-parser accepts a terminator even if a trailing `=` or first hex
        // digit was pending, returning the bytes produced up to that point.
        return Data(output)
    }

    /// Percent decoder used by RFC 2231 extended MIME parameters.
    static func decodePercentEncoded(_ data: Data) -> Data? {
        var output: [UInt8] = []
        output.reserveCapacity(data.count)
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            guard bytes[index] == asciiPercent else {
                output.append(bytes[index])
                index += 1
                continue
            }
            guard index + 2 < bytes.count,
                  let high = hexValue(bytes[index + 1]),
                  let low = hexValue(bytes[index + 2])
            else { return nil }
            output.append((high << 4) | low)
            index += 3
        }

        return Data(output)
    }

    fileprivate static func decodeBase64Word(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        for index in bytes.indices where bytes[index] == asciiLF {
            let next = index + 1
            guard next < bytes.count,
                  bytes[next] == asciiSpace || bytes[next] == asciiTab
            else { return nil }
        }
        return decodeBase64(data, stopAtEncodedWordTerminator: false)?.data
    }

    private static func decodeBase64(
        _ data: Data,
        stopAtEncodedWordTerminator: Bool
    ) -> (data: Data, consumed: Int)? {
        var output: [UInt8] = []
        output.reserveCapacity(data.count / 4 * 3)
        var sextets: [UInt8] = []
        sextets.reserveCapacity(4)
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if stopAtEncodedWordTerminator,
               byte == asciiQuestion,
               index + 1 < bytes.count,
               bytes[index + 1] == asciiEquals {
                return (Data(output), index + 2)
            }

            if let sextet = base64Value(byte) {
                sextets.append(sextet)
                if sextets.count == 4 {
                    appendBase64Quantum(sextets, to: &output)
                    sextets.removeAll(keepingCapacity: true)
                }
            } else {
                switch byte {
                case asciiEquals:
                    flushPaddedBase64Quantum(sextets, to: &output)
                    sextets.removeAll(keepingCapacity: true)
                case asciiSpace, asciiTab, asciiCR, asciiLF:
                    break
                default:
                    return nil
                }
            }
            index += 1
        }

        return stopAtEncodedWordTerminator ? nil : (Data(output), bytes.count)
    }

    private static func appendBase64Quantum(
        _ sextets: [UInt8],
        to output: inout [UInt8]
    ) {
        output.append((sextets[0] << 2) | (sextets[1] >> 4))
        output.append((sextets[1] << 4) | (sextets[2] >> 2))
        output.append((sextets[2] << 6) | sextets[3])
    }

    private static func flushPaddedBase64Quantum(
        _ sextets: [UInt8],
        to output: inout [UInt8]
    ) {
        switch sextets.count {
        case 1:
            output.append(sextets[0] << 2)
        case 2:
            output.append((sextets[0] << 2) | (sextets[1] >> 4))
        case 3:
            output.append((sextets[0] << 2) | (sextets[1] >> 4))
            output.append((sextets[1] << 4) | (sextets[2] >> 2))
        default:
            break
        }
    }

    static func base64Value(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 65...90: byte - 65
        case 97...122: byte - 71
        case 48...57: byte + 4
        case 43: 62
        case 47: 63
        default: nil
        }
    }

    fileprivate static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}

/// RFC 2047 encoded-word decoding shared by all typed textual header parsers.
enum RFC2047Decoder {
    struct DecodedWord: Sendable, Equatable {
        let value: String
        let consumedByteCount: Int
    }

    /// Decodes every valid encoded word, preserving ordinary text and dropping
    /// linear whitespace only between adjacent encoded words.
    static func decodeWords(_ value: String) -> String {
        decodeWords(Array(value.utf8))
    }

    /// Byte-preserving spelling used for RFC 2047 header fields whose encoded
    /// payload may intentionally contain non-UTF-8 octets.
    static func decodeWords<C: Collection>(_ source: C) -> String
    where C.Element == UInt8 {
        let bytes = Array(source)
        var output = ""
        output.reserveCapacity(bytes.count)
        var scan = 0
        var pending = 0
        var previousWasEncoded = false

        while scan + 1 < bytes.count {
            guard bytes[scan] == asciiEquals, bytes[scan + 1] == asciiQuestion,
                  let word = decodeWord(in: bytes, startingAt: scan)
            else {
                scan += 1
                continue
            }

            let separator = bytes[pending..<scan]
            if !previousWasEncoded || !separator.allSatisfy(\.isRFCLinearWhitespace) {
                output += String(decoding: separator, as: UTF8.self)
            }
            output += word.value
            scan += word.consumedByteCount
            pending = scan
            previousWasEncoded = true
        }

        if pending < bytes.count {
            output += String(decoding: bytes[pending...], as: UTF8.self)
        }
        return output
    }

    /// Makes decoded words opaque to a structured parser while retaining raw
    /// non-UTF-8 octets until their declared charset is applied. Each valid
    /// word is decoded exactly once, then represented as a UTF-8 Base64 word
    /// whose payload cannot introduce address punctuation during tokenization.
    static func structurallyOpaqueWords<C: Collection>(_ source: C) -> String
    where C.Element == UInt8 {
        let bytes = Array(source)
        var output = ""
        output.reserveCapacity(bytes.count)
        var scan = 0
        var pending = 0

        while scan + 1 < bytes.count {
            guard bytes[scan] == asciiEquals,
                  bytes[scan + 1] == asciiQuestion,
                  let word = decodeWord(in: bytes, startingAt: scan)
            else {
                scan += 1
                continue
            }

            output += String(decoding: bytes[pending..<scan], as: UTF8.self)
            output += "=?utf-8?b?"
            output += Data(word.value.utf8).base64EncodedString()
            output += "?="
            scan += word.consumedByteCount
            pending = scan
        }

        if pending < bytes.count {
            output += String(decoding: bytes[pending...], as: UTF8.self)
        }
        return output
    }

    /// Parses an RFC 5322 unstructured field while decoding encoded words.
    /// Linear whitespace is collapsed between ordinary tokens, omitted between
    /// adjacent encoded words, and inserted between encoded and ordinary text.
    static func decodeUnstructured<C: Collection>(_ source: C) -> String
    where C.Element == UInt8 {
        let bytes = Array(source)
        var tokens: [String] = []
        tokens.reserveCapacity(4)
        var ordinaryStart: Int?
        var ordinaryEnd = 0
        var lastWasEncoded = true
        var index = 0

        func appendOrdinary() {
            guard let start = ordinaryStart, start < ordinaryEnd else {
                return
            }
            if !tokens.isEmpty {
                tokens.append(" ")
            }
            tokens.append(String(decoding: bytes[start..<ordinaryEnd], as: UTF8.self))
            ordinaryStart = nil
            ordinaryEnd = 0
            lastWasEncoded = false
        }

        while index < bytes.count {
            let byte = bytes[index]

            if byte == asciiLF {
                appendOrdinary()
                index += 1
                if index < bytes.count,
                   bytes[index] == asciiSpace || bytes[index] == asciiTab
                {
                    index += 1
                    continue
                }
                break
            }

            if byte == asciiSpace || byte == asciiTab || byte == asciiCR {
                index += 1
                continue
            }

            if byte == asciiEquals,
               index + 1 < bytes.count,
               bytes[index + 1] == asciiQuestion,
               let word = decodeWord(in: bytes, startingAt: index)
            {
                appendOrdinary()
                if !lastWasEncoded {
                    tokens.append(" ")
                }
                tokens.append(word.value)
                lastWasEncoded = true
                index += word.consumedByteCount
                continue
            }

            if ordinaryStart == nil {
                ordinaryStart = index
            }
            ordinaryEnd = index + 1
            index += 1
        }

        appendOrdinary()
        return tokens.joined()
    }

    /// Decodes one complete encoded word beginning at `startingAt`.
    static func decodeWord(
        in bytes: [UInt8],
        startingAt start: Int
    ) -> DecodedWord? {
        guard start >= 0, start + 4 < bytes.count,
              bytes[start] == asciiEquals, bytes[start + 1] == asciiQuestion
        else { return nil }

        var index = start + 2
        let charsetStart = index
        var charsetEnd: Int?

        while index < bytes.count {
            switch bytes[index] {
            case asciiQuestion:
                let end = charsetEnd ?? index
                guard end - charsetStart >= 2 else { return nil }
                charsetEnd = end
                index += 1
                break
            case asciiAsterisk where charsetEnd == nil:
                charsetEnd = index
                index += 1
            case asciiLF:
                return nil
            default:
                index += 1
            }
            if index > charsetStart, bytes[index - 1] == asciiQuestion { break }
        }

        guard let charsetEnd, index < bytes.count else { return nil }
        let encoding = bytes[index]
        guard encoding == 0x42 || encoding == 0x62
                || encoding == 0x51 || encoding == 0x71
        else { return nil }
        index += 1
        guard index < bytes.count, bytes[index] == asciiQuestion else { return nil }
        index += 1

        let payloadStart = index
        while index + 1 < bytes.count {
            if bytes[index] == asciiQuestion, bytes[index + 1] == asciiEquals {
                let payload = Data(bytes[payloadStart..<index])
                let decoded: Data?
                if encoding == 0x42 || encoding == 0x62 {
                    decoded = TransferDecoder.decodeBase64Word(payload)
                } else {
                    decoded = TransferDecoder.decodeQuotedPrintableWord(payload)
                }
                guard let decoded else { return nil }
                let charset = String(
                    decoding: bytes[charsetStart..<charsetEnd],
                    as: UTF8.self
                )
                return DecodedWord(
                    value: CharsetDecoder.decode(decoded, charset: charset),
                    consumedByteCount: index + 2 - start
                )
            }
            index += 1
        }
        return nil
    }
}

private enum QuotedPrintableState {
    case none
    case equals
    case firstHexDigit
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        switch self {
        case 0x09...0x0D, 0x20: true
        default: false
        }
    }

    var isRFCLinearWhitespace: Bool {
        self == asciiSpace || self == asciiTab || self == asciiCR || self == asciiLF
    }

}

private let asciiTab: UInt8 = 0x09
private let asciiLF: UInt8 = 0x0A
private let asciiCR: UInt8 = 0x0D
private let asciiSpace: UInt8 = 0x20
private let asciiPercent: UInt8 = 0x25
private let asciiAsterisk: UInt8 = 0x2A
private let asciiEquals: UInt8 = 0x3D
private let asciiQuestion: UInt8 = 0x3F
private let asciiUnderscore: UInt8 = 0x5F
