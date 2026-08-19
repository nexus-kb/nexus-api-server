/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 * The streaming MIME state machine in this file is substantially derived
 * from mail-parser 0.11.6's parsers/message.rs and parsers/mime.rs.
 */

import Foundation

/// Internal byte-stream parser used by ``MessageParser``.
///
/// MIME boundaries are deliberately detected while consuming each body rather
/// than by splitting the message into lines first. This preserves mail-parser's
/// permissive boundary-prefix matching and, more importantly, lets malformed
/// nested multiparts recover against the nearest active ancestor boundary.
struct StreamingMIMEParser {
    private static let maximumEncodedMessageDepth = 3

    let rawMessage: Data
    private let bytes: [UInt8]

    init(rawMessage: Data) {
        let normalizedRawMessage = Data(rawMessage)
        self.rawMessage = normalizedRawMessage
        bytes = Array(normalizedRawMessage)
    }

    func parse(skipBody: Bool) -> Message? {
        parse(depthRemaining: Self.maximumEncodedMessageDepth, skipBody: skipBody)
    }

    private func parse(depthRemaining: Int, skipBody: Bool) -> Message? {
        var stream = MIMEByteStream(bytes)
        var message = MutableMessage()
        var state = ParserState.root
        var stack: [ParserFrame] = []
        stack.reserveCapacity(4)
        var partHeaders: [Header] = []

        outer: while true {
            state.offsetHeader = stream.offset
            guard parseHeaders(stream: &stream, headers: &partHeaders) else {
                break
            }
            state.offsetBody = stream.offset
            if skipBody {
                break
            }

            state.parts += 1
            state.subPartIDs.append(message.parts.count)

            let contentType = partHeaders.lastContentType(.contentType)
            var descriptor = MIMEDescriptor(
                contentType: contentType,
                parent: state.mimeType
            )

            if descriptor.isMultipart,
               let boundary = contentType?.attribute(named: "boundary")
            {
                let boundaryBytes = Array(boundary.utf8)
                if stream.seekNextPart(boundary: boundaryBytes) {
                    let partID = message.parts.count
                    let newState = ParserState(
                        mimeType: descriptor.mimeType,
                        mimeBoundary: boundaryBytes,
                        inAlternative: state.inAlternative
                            || descriptor.mimeType == .multipartAlternative,
                        parts: 0,
                        htmlParts: message.htmlBody.count,
                        textParts: message.textBody.count,
                        needHTMLBody: state.needHTMLBody,
                        needTextBody: state.needTextBody,
                        partID: partID,
                        subPartIDs: [],
                        offsetHeader: 0,
                        offsetBody: 0,
                        offsetEnd: 0
                    )
                    message.parts.append(
                        MessagePart(
                            headers: consume(&partHeaders),
                            isEncodingProblem: false,
                            body: .multipart([]),
                            encoding: .none,
                            offsetHeader: state.offsetHeader,
                            offsetBody: state.offsetBody,
                            offsetEnd: 0
                        )
                    )
                    stack.append(ParserFrame(state: state, message: nil))
                    state = newState
                    stream.skipCRLF()
                    continue
                }

                // A declared boundary which never occurs is decoded as an
                // ordinary text attachment, exactly like mail-parser.
                descriptor.mimeType = .textOther
                descriptor.isText = true
            }

            var encoding = transferEncoding(in: partHeaders)

            if descriptor.mimeType == .message, encoding == .none {
                // Direct (unencoded) nested messages stay in the same byte
                // stream so their offsets remain relative to the outer raw
                // message. Move the active boundary to the child state.
                let newState = ParserState(
                    mimeType: .message,
                    mimeBoundary: state.mimeBoundary,
                    inAlternative: false,
                    parts: 0,
                    htmlParts: 0,
                    textParts: 0,
                    needHTMLBody: true,
                    needTextBody: true,
                    partID: message.parts.count,
                    subPartIDs: [],
                    offsetHeader: 0,
                    offsetBody: 0,
                    offsetEnd: 0
                )
                state.mimeBoundary = nil
                message.attachments.append(message.parts.count)
                message.parts.append(
                    MessagePart(
                        headers: consume(&partHeaders),
                        isEncodingProblem: false,
                        body: .multipart([]),
                        encoding: .none,
                        offsetHeader: state.offsetHeader,
                        offsetBody: state.offsetBody,
                        offsetEnd: 0
                    )
                )
                stack.append(ParserFrame(state: state, message: message))
                message = MutableMessage()
                state = newState
                continue
            }

            let decoded: StreamDecodeResult
            switch encoding {
            case .base64:
                decoded = stream.decodeBase64MIME(
                    boundary: state.mimeBoundary ?? []
                )
            case .quotedPrintable:
                decoded = stream.decodeQuotedPrintableMIME(
                    boundary: state.mimeBoundary ?? []
                )
            case .none:
                decoded = stream.readMIMEPart(
                    boundary: state.mimeBoundary ?? []
                )
            }

            var bodyBytes = decoded.data
            var isEncodingProblem = decoded.failed
            if isEncodingProblem {
                encoding = .none
                if descriptor.mimeType != .textPlain {
                    descriptor.mimeType = .textOther
                }
                descriptor.isInline = false
                descriptor.isText = true

                let recovered = stream.seekPartEnd(boundary: state.mimeBoundary)
                state.offsetEnd = recovered.offsetEnd
                bodyBytes = Data(
                    bytes[safe: state.offsetBody..<state.offsetEnd]
                )
                if !recovered.boundaryFound {
                    state.mimeBoundary = nil
                }
            } else {
                state.offsetEnd = decoded.offsetEnd
            }

            let body: PartBody
            if descriptor.mimeType != .message {
                let disposition = partHeaders.lastContentType(.contentDisposition)
                var isInline = descriptor.isInline
                    && disposition?.isAttachment != true
                    && (state.parts == 1
                        || (state.mimeType != .multipartRelated
                            && (descriptor.mimeType == .inline
                                || contentType?.attribute(named: "name") == nil)))

                // Preserve the useful body of a single malformed text/plain
                // message rather than demoting it to an attachment.
                isInline = isInline
                    || (state.parts == 1
                        && state.mimeType == .message
                        && descriptor.mimeType == .textPlain
                        && isEncodingProblem)

                let additions = bodyAdditions(
                    mimeType: descriptor.mimeType,
                    isInline: isInline,
                    state: &state
                )
                if additions.html {
                    message.htmlBody.append(message.parts.count)
                }
                if additions.text {
                    message.textBody.append(message.parts.count)
                }

                if descriptor.isText {
                    let text = CharsetDecoder.decode(
                        bodyBytes,
                        charset: contentType?.attribute(named: "charset")
                    )
                    let isHTML = descriptor.mimeType == .textHTML
                    if (!additions.html && isHTML)
                        || (!additions.text && !isHTML)
                    {
                        message.attachments.append(message.parts.count)
                    }
                    body = isHTML ? .html(text) : .text(text)
                } else {
                    message.attachments.append(message.parts.count)
                    body = isInline
                        ? .inlineBinary(bodyBytes)
                        : .binary(bodyBytes)
                }
            } else {
                message.attachments.append(message.parts.count)
                if depthRemaining > 0,
                   let nested = StreamingMIMEParser(rawMessage: bodyBytes)
                    .parse(depthRemaining: depthRemaining - 1, skipBody: false)
                {
                    body = .message(nested)
                } else {
                    isEncodingProblem = true
                    body = .binary(bodyBytes)
                }
            }

            message.parts.append(
                MessagePart(
                    headers: consume(&partHeaders),
                    isEncodingProblem: isEncodingProblem,
                    body: body,
                    encoding: encoding,
                    offsetHeader: state.offsetHeader,
                    offsetBody: state.offsetBody,
                    offsetEnd: state.offsetEnd
                )
            )

            if state.mimeBoundary != nil {
                inner: while true {
                    if state.mimeType == .message {
                        guard let frame = stack.popLast(),
                              var parentMessage = frame.message
                        else {
                            break outer
                        }

                        let offsetEnd = directMessageEndOffset(
                            stream: stream,
                            boundary: state.mimeBoundary
                        )
                        if message.parts.isEmpty {
                            parentMessage.parts[state.partID] = parentMessage.parts[
                                state.partID
                            ].replacing(
                                body: .text(
                                    String(
                                        decoding: bytes[safe: parentMessage.parts[
                                            state.partID
                                        ].offsetBody..<offsetEnd],
                                        as: UTF8.self
                                    )
                                ),
                                isEncodingProblem: true,
                                offsetEnd: offsetEnd
                            )
                        } else {
                            let nested = message.finalized(rawMessage: rawMessage)
                            parentMessage.parts[state.partID] = parentMessage.parts[
                                state.partID
                            ].replacing(body: .message(nested), offsetEnd: offsetEnd)
                        }

                        message = parentMessage
                        var restoredState = frame.state
                        restoredState.mimeBoundary = state.mimeBoundary
                        state = restoredState
                    }

                    if stream.isMultipartEnd() {
                        completeAlternative(state: state, message: &message)

                        let completedPartID = state.partID
                        guard message.parts.indices.contains(completedPartID) else {
                            break outer
                        }
                        if state.subPartIDs.count != 1
                            || state.subPartIDs.first != 0
                        {
                            message.parts[completedPartID] = message.parts[
                                completedPartID
                            ].replacing(body: .multipart(state.subPartIDs))
                        }

                        if let frame = stack.popLast() {
                            state = frame.state
                            if let ancestorBoundary = state.mimeBoundary,
                               let offset = stream.seekNextPartOffset(
                                   boundary: ancestorBoundary
                               )
                            {
                                message.parts[completedPartID] = message.parts[
                                    completedPartID
                                ].replacing(offsetEnd: offset)
                                continue inner
                            }
                        }

                        if message.parts.indices.contains(completedPartID) {
                            message.parts[completedPartID] = message.parts[
                                completedPartID
                            ]
                                .replacing(offsetEnd: stream.offset)
                        }
                        break outer
                    }
                    break inner
                }
            } else if stream.offset >= stream.count {
                break outer
            }
        }

        // Unwind every unclosed multipart or direct nested-message frame.
        while let frame = stack.popLast() {
            if var parentMessage = frame.message {
                let partID = state.partID
                if parentMessage.parts.indices.contains(partID) {
                    if message.parts.isEmpty {
                        let end = stream.offset
                        let rawText = recoveredDirectMessageText(
                            bodyStart: parentMessage.parts[partID].offsetBody,
                            end: end,
                            boundary: state.mimeBoundary
                        )
                        parentMessage.parts[partID] = parentMessage.parts[partID]
                            .replacing(
                                body: .text(rawText),
                                isEncodingProblem: true,
                                offsetEnd: end
                            )
                    } else {
                        parentMessage.parts[partID] = parentMessage.parts[partID]
                            .replacing(
                                body: .message(
                                    message.finalized(rawMessage: rawMessage)
                                ),
                                offsetEnd: stream.offset
                            )
                    }
                }
                message = parentMessage
            } else if message.parts.indices.contains(state.partID) {
                var part = message.parts[state.partID]
                if state.subPartIDs.count != 1 || state.subPartIDs.first != 0 {
                    part = part.replacing(body: .multipart(state.subPartIDs))
                }
                message.parts[state.partID] = part.replacing(
                    offsetEnd: stream.offset
                )
            }
            state = frame.state
        }

        if !message.parts.isEmpty {
            message.parts[0] = message.parts[0].replacing(
                offsetEnd: rawMessage.count
            )
            return message.finalized(rawMessage: rawMessage)
        }
        if !partHeaders.isEmpty {
            message.parts.append(
                MessagePart(
                    headers: partHeaders,
                    isEncodingProblem: true,
                    body: .text(""),
                    encoding: .none,
                    offsetHeader: 0,
                    offsetBody: rawMessage.count,
                    offsetEnd: rawMessage.count
                )
            )
            return message.finalized(rawMessage: rawMessage)
        }
        return nil
    }
}

private struct MutableMessage {
    var htmlBody: [MessagePartID] = []
    var textBody: [MessagePartID] = []
    var attachments: [MessagePartID] = []
    var parts: [MessagePart] = []

    func finalized(rawMessage: Data) -> Message {
        Message(
            htmlBody: htmlBody,
            textBody: textBody,
            attachments: attachments,
            parts: parts,
            rawMessage: rawMessage
        )
    }
}

private enum StreamingMIMEType: Equatable {
    case multipartMixed
    case multipartAlternative
    case multipartRelated
    case multipartDigest
    case textPlain
    case textHTML
    case textOther
    case inline
    case message
    case other
}

private struct MIMEDescriptor {
    let isMultipart: Bool
    var isInline: Bool
    var isText: Bool
    var mimeType: StreamingMIMEType

    init(contentType: ContentType?, parent: StreamingMIMEType) {
        guard let contentType else {
            isMultipart = false
            isInline = parent != .multipartDigest
            isText = parent != .multipartDigest
            mimeType = parent == .multipartDigest ? .message : .textPlain
            return
        }

        switch contentType.type.lowercased() {
        case "multipart":
            isMultipart = true
            isInline = false
            isText = false
            switch contentType.subtype?.lowercased() {
            case "mixed": mimeType = .multipartMixed
            case "alternative": mimeType = .multipartAlternative
            case "related": mimeType = .multipartRelated
            case "digest": mimeType = .multipartDigest
            default: mimeType = .other
            }
        case "text":
            isMultipart = false
            switch contentType.subtype?.lowercased() {
            case "plain":
                isInline = true
                isText = true
                mimeType = .textPlain
            case "html":
                isInline = true
                isText = true
                mimeType = .textHTML
            default:
                isInline = false
                isText = true
                mimeType = .textOther
            }
        case "image", "audio", "video":
            isMultipart = false
            isInline = true
            isText = false
            mimeType = .inline
        case "message" where contentType.subtype?.caseInsensitiveCompare(
            "rfc822"
        ) == .orderedSame || contentType.subtype?.caseInsensitiveCompare(
            "global"
        ) == .orderedSame:
            isMultipart = false
            isInline = false
            isText = false
            mimeType = .message
        default:
            isMultipart = false
            isInline = false
            isText = false
            mimeType = .other
        }
    }
}

private struct ParserState {
    var mimeType: StreamingMIMEType
    var mimeBoundary: [UInt8]?
    var inAlternative: Bool
    var parts: Int
    var htmlParts: Int
    var textParts: Int
    var needHTMLBody: Bool
    var needTextBody: Bool
    var partID: MessagePartID
    var subPartIDs: [MessagePartID]
    var offsetHeader: Int
    var offsetBody: Int
    var offsetEnd: Int

    static let root = ParserState(
        mimeType: .message,
        mimeBoundary: nil,
        inAlternative: false,
        parts: 0,
        htmlParts: 0,
        textParts: 0,
        needHTMLBody: true,
        needTextBody: true,
        partID: 0,
        subPartIDs: [],
        offsetHeader: 0,
        offsetBody: 0,
        offsetEnd: 0
    )
}

private struct ParserFrame {
    let state: ParserState
    let message: MutableMessage?
}

private struct StreamDecodeResult {
    let offsetEnd: Int
    let data: Data
    let failed: Bool

    static let failure = StreamDecodeResult(
        offsetEnd: .max,
        data: Data(),
        failed: true
    )
}

private struct MIMEByteStream {
    let data: [UInt8]
    private(set) var offset = 0
    private var restoreOffset = 0

    init(_ data: [UInt8]) {
        self.data = data
    }

    var count: Int { data.count }

    mutating func next() -> UInt8? {
        guard offset < data.count else {
            return nil
        }
        defer { offset += 1 }
        return data[offset]
    }

    func peek() -> UInt8? {
        data.indices.contains(offset) ? data[offset] : nil
    }

    mutating func checkpoint() {
        restoreOffset = offset
    }

    mutating func restore() {
        offset = restoreOffset
        restoreOffset = 0
    }

    mutating func trySkip(_ value: [UInt8]) -> Bool {
        guard !value.isEmpty,
              offset <= data.count,
              value.count <= data.count - offset,
              data[offset..<(offset + value.count)].elementsEqual(value)
        else {
            return false
        }
        offset += value.count
        return true
    }

    mutating func seekNextPart(boundary: [UInt8]) -> Bool {
        guard !boundary.isEmpty else {
            return false
        }
        var last: UInt8 = 0
        checkpoint()
        while let byte = next() {
            if byte == 0x2D, last == 0x2D, trySkip(boundary) {
                return true
            }
            last = byte
        }
        restore()
        return false
    }

    mutating func seekNextPartOffset(boundary: [UInt8]) -> Int? {
        var last: UInt8 = 0x0A
        var offsetPosition = offset
        checkpoint()
        while let byte = next() {
            if byte == 0x0A {
                offsetPosition = last == 0x0D ? offset - 2 : offset - 1
            } else if byte == 0x2D, last == 0x2D, trySkip(boundary) {
                return offsetPosition
            }
            last = byte
        }
        restore()
        return nil
    }

    mutating func readMIMEPart(boundary: [UInt8]) -> StreamDecodeResult {
        var last: UInt8 = 0x0A
        var beforeLast: UInt8 = 0
        let start = offset
        var end = offset
        checkpoint()

        while let byte = next() {
            if byte == 0x0A {
                end = last == 0x0D ? offset - 2 : offset - 1
            } else if byte == 0x2D,
                      !boundary.isEmpty,
                      last == 0x2D,
                      trySkip(boundary)
            {
                if beforeLast != 0x0A {
                    end = offset - boundary.count - 2
                }
                return StreamDecodeResult(
                    offsetEnd: end,
                    data: Data(data[safe: start..<end]),
                    failed: false
                )
            }
            beforeLast = last
            last = byte
        }

        if boundary.isEmpty {
            return StreamDecodeResult(
                offsetEnd: offset,
                data: Data(data[safe: start..<data.count]),
                failed: false
            )
        }
        restore()
        return .failure
    }

    mutating func decodeBase64MIME(
        boundary: [UInt8]
    ) -> StreamDecodeResult {
        var sextets: [UInt8] = []
        sextets.reserveCapacity(4)
        var output: [UInt8] = []
        output.reserveCapacity(max(0, data.count - offset) / 4 * 3)
        var last: UInt8 = 0x0A
        var beforeLast: UInt8 = 0
        var end = offset
        checkpoint()

        while let byte = next() {
            if let sextet = byte.base64Sextet {
                sextets.append(sextet)
                if sextets.count == 4 {
                    appendBase64(sextets, to: &output)
                    sextets.removeAll(keepingCapacity: true)
                }
            } else {
                switch byte {
                case 0x3D: // =
                    switch sextets.count {
                    case 1, 2:
                        output.append(sextets[0] << 2
                            | (sextets.count > 1 ? sextets[1] >> 4 : 0))
                        sextets.removeAll(keepingCapacity: true)
                    case 3:
                        output.append(sextets[0] << 2 | sextets[1] >> 4)
                        output.append(sextets[1] << 4 | sextets[2] >> 2)
                        sextets.removeAll(keepingCapacity: true)
                    case 0:
                        break
                    default:
                        restore()
                        return .failure
                    }
                case 0x0A:
                    end = last == 0x0D ? offset - 2 : offset - 1
                case 0x20, 0x09, 0x0D:
                    break
                case 0x2D: // -
                    if last == 0x2D {
                        if !boundary.isEmpty, trySkip(boundary) {
                            let offsetEnd = beforeLast == 0x0A
                                ? end
                                : offset - boundary.count - 2
                            return StreamDecodeResult(
                                offsetEnd: offsetEnd,
                                data: Data(output),
                                failed: false
                            )
                        }
                        restore()
                        return .failure
                    }
                default:
                    restore()
                    return .failure
                }
            }
            beforeLast = last
            last = byte
        }

        if boundary.isEmpty {
            return StreamDecodeResult(
                offsetEnd: offset,
                data: Data(output),
                failed: false
            )
        }
        restore()
        return .failure
    }

    mutating func decodeQuotedPrintableMIME(
        boundary: [UInt8]
    ) -> StreamDecodeResult {
        enum State: Equatable {
            case none
            case equals
            case firstHex
        }

        var output: [UInt8] = []
        output.reserveCapacity(128)
        var state = State.none
        var highNibble = 0
        var last: UInt8 = 0
        var beforeLast: UInt8 = 0
        var whitespaceCount = 0
        var end = offset
        var lineEnding: [UInt8] = [0x0A]
        checkpoint()

        while let byte = next() {
            switch byte {
            case 0x3D: // =
                guard state == .none else {
                    restore()
                    return .failure
                }
                state = .equals
            case 0x0A:
                end = last == 0x0D ? offset - 2 : offset - 1
                if state == .equals {
                    state = .none
                } else {
                    if whitespaceCount > 0 {
                        output.removeLast(min(whitespaceCount, output.count))
                    }
                    output.append(contentsOf: lineEnding)
                }
                whitespaceCount = 0
            case 0x0D:
                lineEnding = [0x0D, 0x0A]
            case 0x2D where !boundary.isEmpty
                && last == 0x2D
                && trySkip(boundary):
                if beforeLast == 0x0A {
                    output.removeLast(min(lineEnding.count + 1, output.count))
                } else {
                    if !output.isEmpty {
                        output.removeLast()
                    }
                    end = offset - boundary.count - 2
                }
                return StreamDecodeResult(
                    offsetEnd: end,
                    data: Data(output),
                    failed: false
                )
            default:
                switch state {
                case .none:
                    if byte.isASCIIWhitespace {
                        whitespaceCount += 1
                    } else {
                        whitespaceCount = 0
                    }
                    output.append(byte)
                case .equals:
                    if let nibble = byte.hexNibble {
                        highNibble = Int(nibble)
                        state = .firstHex
                    } else if !byte.isASCIIWhitespace {
                        state = .none
                        output.append(0x3D)
                        output.append(byte)
                        whitespaceCount = 0
                    }
                case .firstHex:
                    state = .none
                    if let low = byte.hexNibble {
                        output.append(UInt8(highNibble << 4) | low)
                    } else {
                        output.append(0x3D)
                        output.append(last)
                        output.append(byte)
                    }
                    whitespaceCount = 0
                }
            }
            beforeLast = last
            last = byte
        }

        if boundary.isEmpty {
            return StreamDecodeResult(
                offsetEnd: offset,
                data: Data(output),
                failed: false
            )
        }
        restore()
        return .failure
    }

    mutating func seekPartEnd(boundary: [UInt8]?) -> (
        offsetEnd: Int,
        boundaryFound: Bool
    ) {
        var last: UInt8 = 0x0A
        var beforeLast: UInt8 = 0
        var end = offset

        if let boundary {
            while let byte = next() {
                if byte == 0x0A {
                    end = last == 0x0D ? offset - 2 : offset - 1
                } else if byte == 0x2D,
                          last == 0x2D,
                          trySkip(boundary)
                {
                    if beforeLast != 0x0A {
                        end = offset - boundary.count - 2
                    }
                    return (end, true)
                }
                beforeLast = last
                last = byte
            }
            return (offset, false)
        }

        offset = data.count
        return (offset, true)
    }

    mutating func isMultipartEnd() -> Bool {
        checkpoint()
        switch (next(), peek()) {
        case (0x0D?, 0x0A?):
            _ = next()
            return false
        case (0x2D?, 0x2D?):
            _ = next()
            return true
        case (0x0A?, _):
            return false
        case (let byte?, _) where byte.isASCIIWhitespace:
            skipCRLF()
            return false
        default:
            restore()
            return false
        }
    }

    mutating func skipCRLF() {
        while let byte = peek() {
            switch byte {
            case 0x0D, 0x20, 0x09:
                _ = next()
            case 0x0A:
                _ = next()
                return
            default:
                return
            }
        }
    }
}

private func appendBase64(_ sextets: [UInt8], to output: inout [UInt8]) {
    guard sextets.count == 4 else {
        return
    }
    output.append(sextets[0] << 2 | sextets[1] >> 4)
    output.append(sextets[1] << 4 | sextets[2] >> 2)
    output.append(sextets[2] << 6 | sextets[3])
}

private extension StreamingMIMEParser {
    func parseHeaders(
        stream: inout MIMEByteStream,
        headers: inout [Header]
    ) -> Bool {
        while true {
            while let byte = stream.peek() {
                if byte == 0x0A {
                    _ = stream.next()
                    return true
                }
                if !byte.isASCIIWhitespace {
                    break
                }
                _ = stream.next()
            }
            guard stream.peek() != nil else {
                return false
            }

            let offsetField = stream.offset
            guard let name = parseHeaderName(stream: &stream) else {
                if stream.peek() == nil {
                    return false
                }
                continue
            }

            let offsetStart = stream.offset
            let offsetEnd = consumeHeaderValue(stream: &stream)
            headers.append(
                Header(
                    name: name,
                    value: parsedHeaderValue(
                        name: name,
                        range: offsetStart..<offsetEnd
                    ),
                    offsetField: offsetField,
                    offsetStart: offsetStart,
                    offsetEnd: offsetEnd
                )
            )
        }
    }

    func parseHeaderName(stream: inout MIMEByteStream) -> HeaderName? {
        var tokenStart: Int?
        var tokenEnd = 0
        var mapped: [UInt8] = []
        mapped.reserveCapacity(30)

        while let byte = stream.next() {
            switch byte {
            case 0x3A where tokenStart != nil:
                let original = String(
                    decoding: bytes[safe: tokenStart!..<tokenEnd],
                    as: UTF8.self
                )
                if mapped.count <= 30,
                   let recognized = recognizedHeaderName(mapped)
                {
                    return recognized
                }
                return .other(original)
            case 0x0A:
                return nil
            default:
                if !byte.isASCIIWhitespace {
                    if tokenStart == nil {
                        tokenStart = stream.offset - 1
                    }
                    tokenEnd = stream.offset
                    if mapped.count < 30 {
                        mapped.append(byte.asciiLowercased)
                    }
                }
            }
        }
        return nil
    }

    func consumeHeaderValue(stream: inout MIMEByteStream) -> Int {
        while let byte = stream.next() {
            guard byte == 0x0A else {
                continue
            }
            if let next = stream.peek(), next == 0x20 || next == 0x09 {
                continue
            }
            return stream.offset
        }
        return stream.offset
    }

    func parsedHeaderValue(
        name: HeaderName,
        range: Range<Int>
    ) -> HeaderValue {
        let rawBytes = Array(bytes[safe: range])
        let raw = String(decoding: rawBytes, as: UTF8.self)
        let logicalBytes = unfold(rawBytes)
        let logical = String(decoding: logicalBytes, as: UTF8.self)

        switch name {
        case .subject, .comments, .contentDescription, .contentLocation,
             .contentTransferEncoding:
            let value = RFC2047Decoder.decodeUnstructured(rawBytes)
            return value.isEmpty ? .empty : .text(value)

        case .from, .to, .cc, .bcc, .replyTo, .sender,
             .resentTo, .resentFrom, .resentBcc, .resentCc, .resentSender,
             .listArchive, .listHelp, .listID, .listOwner, .listPost,
             .listSubscribe, .listUnsubscribe:
            return AddressParser().parse(logicalBytes).map(HeaderValue.address)
                ?? .empty

        case .date, .resentDate:
            return MailDateParser.parse(raw).map(HeaderValue.dateTime)
                ?? .empty

        case .messageID, .references, .inReplyTo, .returnPath, .contentID,
             .resentMessageID:
            let values = RFCMessageIDParser.parse(raw)
            if values.count == 1, let value = values.first {
                return .text(value)
            }
            return values.isEmpty ? .empty : .textList(values)

        case .keywords, .contentLanguage:
            let values = parseCommaList(logical)
            if values.count == 1, let value = values.first {
                return .text(value)
            }
            return values.isEmpty ? .empty : .textList(values)

        case .received:
            return ReceivedParser.parse(raw).map(HeaderValue.received)
                ?? .empty

        case .contentType, .contentDisposition:
            return MIMEParameterParser.parse(raw).map(HeaderValue.contentType)
                ?? .empty

        case .mimeVersion, .dkimSignature, .arcAuthenticationResults,
             .arcMessageSignature, .arcSeal, .dkim2Signature,
             .messageInstance, .other:
            let value = rawHeaderText(rawBytes)
            return value.isEmpty ? .empty : .text(value)
        }
    }

    func unfold(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        var index = 0

        while index < input.count {
            if input[index] == 0x0D,
               index + 2 < input.count,
               input[index + 1] == 0x0A,
               input[index + 2] == 0x20 || input[index + 2] == 0x09
            {
                index += 2
            } else if input[index] == 0x0A,
                      index + 1 < input.count,
                      input[index + 1] == 0x20 || input[index + 1] == 0x09
            {
                index += 1
            } else if input[index] == 0x0D || input[index] == 0x0A {
                break
            } else {
                output.append(input[index])
                index += 1
                continue
            }

            while index < input.count,
                  input[index] == 0x20 || input[index] == 0x09
            {
                index += 1
            }
            if !output.isEmpty, output.last != 0x20 {
                output.append(0x20)
            }
        }

        var start = 0
        var end = output.count
        while start < end,
              output[start] == 0x20 || output[start] == 0x09
        {
            start += 1
        }
        while end > start,
              output[end - 1] == 0x20 || output[end - 1] == 0x09
        {
            end -= 1
        }
        guard start != 0 || end != output.count else {
            return output
        }
        return Array(output[start..<end])
    }

    func rawHeaderText(_ input: [UInt8]) -> String {
        var start = 0
        var end = input.count
        while start < end, input[start].isRFCHeaderWhitespace {
            start += 1
        }
        while end > start, input[end - 1].isRFCHeaderWhitespace {
            end -= 1
        }
        return String(decoding: input[start..<end], as: UTF8.self)
    }

    func parseCommaList(_ source: String) -> [String] {
        source.split(separator: ",", omittingEmptySubsequences: true)
            .map {
                RFC2047Decoder.decodeWords(
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.isEmpty }
    }

    func recognizedHeaderName(_ lowercased: [UInt8]) -> HeaderName? {
        switch String(decoding: lowercased, as: UTF8.self) {
        case "subject": .subject
        case "from": .from
        case "to": .to
        case "cc": .cc
        case "date": .date
        case "bcc": .bcc
        case "reply-to": .replyTo
        case "sender": .sender
        case "comments": .comments
        case "in-reply-to": .inReplyTo
        case "keywords": .keywords
        case "received": .received
        case "message-id": .messageID
        case "references": .references
        case "return-path": .returnPath
        case "mime-version": .mimeVersion
        case "content-description": .contentDescription
        case "content-id": .contentID
        case "content-language": .contentLanguage
        case "content-location": .contentLocation
        case "content-transfer-encoding": .contentTransferEncoding
        case "content-type": .contentType
        case "content-disposition": .contentDisposition
        case "resent-to": .resentTo
        case "resent-from": .resentFrom
        case "resent-bcc": .resentBcc
        case "resent-cc": .resentCc
        case "resent-sender": .resentSender
        case "resent-date": .resentDate
        case "resent-message-id": .resentMessageID
        case "list-archive": .listArchive
        case "list-help": .listHelp
        case "list-id": .listID
        case "list-owner": .listOwner
        case "list-post": .listPost
        case "list-subscribe": .listSubscribe
        case "list-unsubscribe": .listUnsubscribe
        case "dkim-signature": .dkimSignature
        case "arc-authentication-results": .arcAuthenticationResults
        case "arc-message-signature": .arcMessageSignature
        case "arc-seal": .arcSeal
        case "dkim2-signature": .dkim2Signature
        case "message-instance": .messageInstance
        default: nil
        }
    }

    func transferEncoding(in headers: [Header]) -> TransferEncoding {
        let value = headers.last {
            $0.name == .contentTransferEncoding
        }?.value.text?.trimmingCharacters(in: .whitespacesAndNewlines)

        if value?.caseInsensitiveCompare("base64") == .orderedSame {
            return .base64
        }
        if value?.caseInsensitiveCompare("quoted-printable") == .orderedSame {
            return .quotedPrintable
        }
        return .none
    }

    func bodyAdditions(
        mimeType: StreamingMIMEType,
        isInline: Bool,
        state: inout ParserState
    ) -> (html: Bool, text: Bool) {
        if state.mimeType == .multipartAlternative {
            switch mimeType {
            case .textHTML: return (true, false)
            case .textPlain: return (false, true)
            default: return (false, false)
            }
        }

        if isInline {
            if state.inAlternative
                && (state.needTextBody || state.needHTMLBody)
            {
                switch mimeType {
                case .textHTML:
                    state.needTextBody = false
                case .textPlain:
                    state.needHTMLBody = false
                default:
                    break
                }
            }
            return (state.needHTMLBody, state.needTextBody)
        }
        return (false, false)
    }

    func completeAlternative(
        state: ParserState,
        message: inout MutableMessage
    ) {
        guard state.mimeType == .multipartAlternative,
              state.needHTMLBody,
              state.needTextBody
        else {
            return
        }

        if state.textParts == message.textBody.count,
           state.htmlParts != message.htmlBody.count
        {
            message.textBody.append(
                contentsOf: message.htmlBody[state.htmlParts...]
            )
        }
        if state.htmlParts == message.htmlBody.count,
           state.textParts != message.textBody.count
        {
            message.htmlBody.append(
                contentsOf: message.textBody[state.textParts...]
            )
        }
    }

    func directMessageEndOffset(
        stream: MIMEByteStream,
        boundary: [UInt8]?
    ) -> Int {
        guard let boundary else {
            return stream.offset
        }
        let position = stream.offset - boundary.count - 2
        guard position > 0 else {
            return max(0, position)
        }
        return bytes.indices.contains(position - 2)
            && bytes[position - 2] == 0x0D
            ? position - 2
            : position - 1
    }

    func recoveredDirectMessageText(
        bodyStart: Int,
        end: Int,
        boundary: [UInt8]?
    ) -> String {
        let raw = Array(bytes[safe: bodyStart..<end])
        guard let boundary,
              boundary.count <= raw.count,
              let boundaryStart = raw.lastRange(of: boundary)?.lowerBound,
              boundaryStart >= 2,
              raw[boundaryStart - 2] == 0x2D,
              raw[boundaryStart - 1] == 0x2D
        else {
            return String(decoding: raw, as: UTF8.self)
        }
        var textEnd = boundaryStart - 2
        if textEnd > 0, raw[textEnd - 1] == 0x0A {
            textEnd -= 1
        }
        if textEnd > 0, raw[textEnd - 1] == 0x0D {
            textEnd -= 1
        }
        return String(decoding: raw[..<textEnd], as: UTF8.self)
    }
}

private func consume<T>(_ value: inout [T]) -> [T] {
    let result = value
    value.removeAll(keepingCapacity: true)
    return result
}

private extension Array where Element == Header {
    func lastContentType(_ name: HeaderName) -> ContentType? {
        last { $0.name == name }?.value.contentType
    }
}

private extension MessagePart {
    func replacing(
        body: PartBody? = nil,
        isEncodingProblem: Bool? = nil,
        offsetEnd: Int? = nil
    ) -> MessagePart {
        MessagePart(
            headers: headers,
            isEncodingProblem: isEncodingProblem ?? self.isEncodingProblem,
            body: body ?? self.body,
            encoding: encoding,
            offsetHeader: offsetHeader,
            offsetBody: offsetBody,
            offsetEnd: offsetEnd ?? self.offsetEnd
        )
    }
}

private extension Array where Element == UInt8 {
    subscript(safe range: Range<Int>) -> ArraySlice<UInt8> {
        let lower = Swift.max(0, Swift.min(count, range.lowerBound))
        let upper = Swift.max(lower, Swift.min(count, range.upperBound))
        return self[lower..<upper]
    }


    func lastRange(of needle: [UInt8]) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= count else {
            return nil
        }
        var index = count - needle.count
        while true {
            if self[index..<(index + needle.count)].elementsEqual(needle) {
                return index..<(index + needle.count)
            }
            if index == 0 {
                return nil
            }
            index -= 1
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0D || self == 0x0A
            || self == 0x0B || self == 0x0C
    }

    var isRFCHeaderWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0D || self == 0x0A
    }

    var asciiLowercased: UInt8 {
        (0x41...0x5A).contains(self) ? self + 0x20 : self
    }

    var base64Sextet: UInt8? {
        switch self {
        case 0x41...0x5A: self - 0x41
        case 0x61...0x7A: self - 0x61 + 26
        case 0x30...0x39: self - 0x30 + 52
        case 0x2B: 62
        case 0x2F: 63
        default: nil
        }
    }

    var hexNibble: UInt8? {
        switch self {
        case 0x30...0x39: self - 0x30
        case 0x41...0x46: self - 0x41 + 10
        case 0x61...0x66: self - 0x61 + 10
        default: nil
        }
    }
}
