//
// SPDX-License-Identifier: Apache-2.0 OR MIT
//

import Foundation

public typealias MessagePartID = Int

public struct Message: Sendable, Equatable, Codable {
    public let htmlBody: [MessagePartID]
    public let textBody: [MessagePartID]
    public let attachments: [MessagePartID]
    public let parts: [MessagePart]
    public let rawMessage: Data

    public init(
        htmlBody: [MessagePartID],
        textBody: [MessagePartID],
        attachments: [MessagePartID],
        parts: [MessagePart],
        rawMessage: Data
    ) {
        self.htmlBody = htmlBody
        self.textBody = textBody
        self.attachments = attachments
        self.parts = parts
        self.rawMessage = Data(rawMessage)
    }

    public var rootPart: MessagePart? {
        parts.first
    }

    public var headers: [Header] {
        rootPart?.headers ?? []
    }

    public func header(_ name: HeaderName) -> HeaderValue? {
        headers.last { $0.name == name }?.value
    }

    public func header(named name: String) -> HeaderValue? {
        guard let headerName = HeaderName(name) else {
            return nil
        }

        return header(headerName)
    }

    public func headerValues(_ name: HeaderName) -> [HeaderValue] {
        headers.compactMap { header in
            header.name == name ? header.value : nil
        }
    }

    public func headerValues(named name: String) -> [HeaderValue] {
        guard let headerName = HeaderName(name) else {
            return []
        }

        return headerValues(headerName)
    }

    public func rawHeader(_ name: HeaderName) -> String? {
        headers.last(where: { $0.name == name }).flatMap(rawValue(for:))
    }

    public func rawHeader(named name: String) -> String? {
        guard let headerName = HeaderName(name) else {
            return nil
        }

        return rawHeader(headerName)
    }

    public func rawHeaderValues(_ name: HeaderName) -> [String] {
        headers.compactMap { header in
            header.name == name ? rawValue(for: header) : nil
        }
    }

    public func rawHeaderValues(named name: String) -> [String] {
        guard let headerName = HeaderName(name) else {
            return []
        }

        return rawHeaderValues(headerName)
    }

    public var subject: String? {
        header(.subject)?.text
    }

    public var threadName: String? {
        subject.flatMap(ThreadNameParser.threadName)
    }

    public var baseSubject: String? {
        threadName
    }

    public var messageID: String? {
        header(.messageID)?.text
    }

    public var messageIDs: [String] {
        allTextValues(for: .messageID)
    }

    public var inReplyToIDs: [String] {
        allTextValues(for: .inReplyTo)
    }

    public var inReplyToID: String? {
        header(.inReplyTo)?.text
    }

    public var referenceIDs: [String] {
        allTextValues(for: .references)
    }

    public var referenceID: String? {
        header(.references)?.text
    }

    public var resentMessageID: String? {
        header(.resentMessageID)?.text
    }

    public var resentMessageIDs: [String] {
        allTextValues(for: .resentMessageID)
    }

    public var returnPath: String? {
        header(.returnPath)?.text
    }

    public var returnPathIDs: [String] {
        allTextValues(for: .returnPath)
    }

    public var contentID: String? {
        header(.contentID)?.text
    }

    public var contentIDs: [String] {
        allTextValues(for: .contentID)
    }

    public var messageInstance: String? {
        header(.messageInstance)?.text
    }

    public var messageInstances: [String] {
        allTextValues(for: .messageInstance)
    }

    public var returnAddress: String? {
        returnPath ?? from?.first?.address
    }

    public var from: Address? {
        header(.from)?.address
    }

    public var to: Address? {
        header(.to)?.address
    }

    public var cc: Address? {
        header(.cc)?.address
    }

    public var bcc: Address? {
        header(.bcc)?.address
    }

    public var replyTo: Address? {
        header(.replyTo)?.address
    }

    public var sender: Address? {
        header(.sender)?.address
    }

    public var allFrom: [Address] {
        allAddresses(for: .from)
    }

    public var allTo: [Address] {
        allAddresses(for: .to)
    }

    public var allCc: [Address] {
        allAddresses(for: .cc)
    }

    public var allBcc: [Address] {
        allAddresses(for: .bcc)
    }

    public var allReplyTo: [Address] {
        allAddresses(for: .replyTo)
    }

    public var allSender: [Address] {
        allAddresses(for: .sender)
    }

    public var resentFrom: Address? {
        header(.resentFrom)?.address
    }

    public var resentTo: Address? {
        header(.resentTo)?.address
    }

    public var resentCc: Address? {
        header(.resentCc)?.address
    }

    public var resentBcc: Address? {
        header(.resentBcc)?.address
    }

    public var resentSender: Address? {
        header(.resentSender)?.address
    }

    public var allResentFrom: [Address] {
        allAddresses(for: .resentFrom)
    }

    public var allResentTo: [Address] {
        allAddresses(for: .resentTo)
    }

    public var allResentCc: [Address] {
        allAddresses(for: .resentCc)
    }

    public var allResentBcc: [Address] {
        allAddresses(for: .resentBcc)
    }

    public var allResentSender: [Address] {
        allAddresses(for: .resentSender)
    }

    public var date: MailDateTime? {
        header(.date)?.dateTime
    }

    public var dates: [MailDateTime] {
        headerValues(.date).compactMap(\.dateTime)
    }

    public var resentDate: MailDateTime? {
        header(.resentDate)?.dateTime
    }

    public var resentDates: [MailDateTime] {
        headerValues(.resentDate).compactMap(\.dateTime)
    }

    public var comments: String? {
        header(.comments)?.text
    }

    public var keywords: [String] {
        allTextValues(for: .keywords)
    }

    public var listArchive: Address? {
        header(.listArchive)?.address
    }

    public var listHelp: Address? {
        header(.listHelp)?.address
    }

    public var listID: Address? {
        header(.listID)?.address
    }

    public var listOwner: Address? {
        header(.listOwner)?.address
    }

    public var listPost: Address? {
        header(.listPost)?.address
    }

    public var listSubscribe: Address? {
        header(.listSubscribe)?.address
    }

    public var listUnsubscribe: Address? {
        header(.listUnsubscribe)?.address
    }

    public var mimeVersion: String? {
        header(.mimeVersion)?.text
    }

    public var contentType: ContentType? {
        header(.contentType)?.contentType
    }

    public var contentDisposition: ContentType? {
        header(.contentDisposition)?.contentType
    }

    public var contentDescription: String? {
        header(.contentDescription)?.text
    }

    public var contentLanguage: [String] {
        allTextValues(for: .contentLanguage)
    }

    public var contentLocation: String? {
        header(.contentLocation)?.text
    }

    public var contentTransferEncoding: String? {
        header(.contentTransferEncoding)?.text
    }

    public var received: Received? {
        receivedAll.last
    }

    public var receivedAll: [Received] {
        headerValues(.received).compactMap(\.received)
    }

    public func allAddresses(for name: HeaderName) -> [Address] {
        headerValues(name).compactMap(\.address)
    }

    public func allTextValues(for name: HeaderName) -> [String] {
        headerValues(name).flatMap(\.textValues)
    }

    public func part(at id: MessagePartID) -> MessagePart? {
        parts.indices.contains(id) ? parts[id] : nil
    }

    public func textPart(at index: Int) -> MessagePart? {
        guard textBody.indices.contains(index) else {
            return nil
        }

        return part(at: textBody[index])
    }

    public func htmlPart(at index: Int) -> MessagePart? {
        guard htmlBody.indices.contains(index) else {
            return nil
        }

        return part(at: htmlBody[index])
    }

    public func attachment(at index: Int) -> MessagePart? {
        guard attachments.indices.contains(index) else {
            return nil
        }

        return part(at: attachments[index])
    }

    public var textBodyCount: Int {
        textBody.count
    }

    public var htmlBodyCount: Int {
        htmlBody.count
    }

    public var attachmentCount: Int {
        attachments.count
    }

    public var textParts: [MessagePart] {
        textBody.compactMap(part(at:))
    }

    public var htmlParts: [MessagePart] {
        htmlBody.compactMap(part(at:))
    }

    public var attachmentParts: [MessagePart] {
        attachments.compactMap(part(at:))
    }

    public var attachmentNames: [String?] {
        attachmentParts.map(\.attachmentName)
    }

    public func attachmentName(at index: Int) -> String? {
        attachment(at: index)?.attachmentName
    }

    public func bodyText(at index: Int) -> String? {
        guard let part = textPart(at: index) else {
            return nil
        }

        switch part.body {
        case .text(let text):
            return text
        case .html(let html):
            return HTMLConverter.htmlToText(html)
        default:
            return nil
        }
    }

    public func bodyHTML(at index: Int) -> String? {
        guard let part = htmlPart(at: index) else {
            return nil
        }

        switch part.body {
        case .html(let html):
            return html
        case .text(let text):
            return HTMLConverter.textToHTML(text)
        default:
            return nil
        }
    }

    public func bodyPreview(maxLength: Int) -> String? {
        guard maxLength >= 0 else {
            return nil
        }

        if !textBody.isEmpty, let text = bodyText(at: 0) {
            return HTMLConverter.previewText(text, maxLength: maxLength)
        }

        if !htmlBody.isEmpty, let html = bodyHTML(at: 0) {
            return HTMLConverter.previewHTML(html, maxLength: maxLength)
        }

        return nil
    }

    private func rawValue(for header: Header) -> String? {
        guard header.offsetStart >= 0,
              header.offsetStart <= header.offsetEnd,
              header.offsetEnd <= rawMessage.count
        else {
            return nil
        }

        return String(
            decoding: rawMessage[header.offsetStart..<header.offsetEnd],
            as: UTF8.self
        )
        .trimmingCharacters(in: .newlines)
    }
}

public struct MessagePart: Sendable, Equatable, Codable {
    public let headers: [Header]
    public let isEncodingProblem: Bool
    public let body: PartBody
    public let encoding: TransferEncoding
    public let offsetHeader: Int
    public let offsetBody: Int
    public let offsetEnd: Int

    public init(
        headers: [Header],
        isEncodingProblem: Bool,
        body: PartBody,
        encoding: TransferEncoding,
        offsetHeader: Int,
        offsetBody: Int,
        offsetEnd: Int
    ) {
        self.headers = headers
        self.isEncodingProblem = isEncodingProblem
        self.body = body
        self.encoding = encoding
        self.offsetHeader = offsetHeader
        self.offsetBody = offsetBody
        self.offsetEnd = offsetEnd
    }

    public func header(_ name: HeaderName) -> HeaderValue? {
        headers.last { $0.name == name }?.value
    }

    public func header(named name: String) -> HeaderValue? {
        guard let headerName = HeaderName(name) else {
            return nil
        }

        return header(headerName)
    }

    public func headerValues(_ name: HeaderName) -> [HeaderValue] {
        headers.compactMap { header in
            header.name == name ? header.value : nil
        }
    }

    public func headerValues(named name: String) -> [HeaderValue] {
        guard let headerName = HeaderName(name) else {
            return []
        }

        return headerValues(headerName)
    }

    public var contentType: ContentType? {
        header(.contentType)?.contentType
    }

    public var contentDisposition: ContentType? {
        header(.contentDisposition)?.contentType
    }

    public var contentID: String? {
        header(.contentID)?.text
    }

    public var contentIDs: [String] {
        headerValues(.contentID).flatMap(\.textValues)
    }

    public var contentDescription: String? {
        header(.contentDescription)?.text
    }

    public var contentLanguage: [String] {
        headerValues(.contentLanguage).flatMap(\.textValues)
    }

    public var contentLocation: String? {
        header(.contentLocation)?.text
    }

    public var contentTransferEncoding: String? {
        header(.contentTransferEncoding)?.text
    }

    public var attachmentName: String? {
        contentDisposition?.attribute(named: "filename")
            ?? contentType?.attribute(named: "name")
    }

    public var rawLength: Int {
        guard offsetEnd >= offsetHeader else {
            return 0
        }
        let (length, overflow) = offsetEnd.subtractingReportingOverflow(
            offsetHeader
        )
        return overflow ? 0 : length
    }

    public var decodedLength: Int {
        switch body {
        case .text(let value), .html(let value):
            value.utf8.count
        case .binary(let value), .inlineBinary(let value):
            value.count
        case .message(let value):
            value.rootPart?.rawLength
                ?? value.rawMessage.count
        case .multipart:
            0
        }
    }

    public var isText: Bool {
        switch body {
        case .text, .html: true
        default: false
        }
    }

    public var isHTML: Bool {
        if case .html = body { true } else { false }
    }

    public var isBinary: Bool {
        switch body {
        case .binary, .inlineBinary: true
        default: false
        }
    }

    public var isMultipart: Bool {
        if case .multipart = body { true } else { false }
    }

    public var isNestedMessage: Bool {
        if case .message = body { true } else { false }
    }

    public var nestedMessage: Message? {
        if case .message(let value) = body { value } else { nil }
    }

    public var childPartIDs: [MessagePartID]? {
        if case .multipart(let value) = body { value } else { nil }
    }
}

public indirect enum PartBody: Sendable, Equatable {
    case text(String)
    case html(String)
    case binary(Data)
    case inlineBinary(Data)
    case message(Message)
    case multipart([MessagePartID])
}

extension PartBody: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case message
        case parts
    }

    private enum Kind: String, Codable {
        case text
        case html
        case binary
        case inlineBinary
        case message
        case multipart
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .html:
            self = .html(try container.decode(String.self, forKey: .text))
        case .binary:
            self = .binary(try container.decode(Data.self, forKey: .data))
        case .inlineBinary:
            self = .inlineBinary(try container.decode(Data.self, forKey: .data))
        case .message:
            self = .message(try container.decode(Message.self, forKey: .message))
        case .multipart:
            self = .multipart(try container.decode([MessagePartID].self, forKey: .parts))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .html(let value):
            try container.encode(Kind.html, forKey: .type)
            try container.encode(value, forKey: .text)
        case .binary(let value):
            try container.encode(Kind.binary, forKey: .type)
            try container.encode(value, forKey: .data)
        case .inlineBinary(let value):
            try container.encode(Kind.inlineBinary, forKey: .type)
            try container.encode(value, forKey: .data)
        case .message(let value):
            try container.encode(Kind.message, forKey: .type)
            try container.encode(value, forKey: .message)
        case .multipart(let value):
            try container.encode(Kind.multipart, forKey: .type)
            try container.encode(value, forKey: .parts)
        }
    }
}

public enum TransferEncoding: String, Sendable, Equatable, Codable {
    case none
    case quotedPrintable
    case base64
}

public struct Header: Sendable, Equatable, Codable {
    public let name: HeaderName
    public let value: HeaderValue
    public let offsetField: Int
    public let offsetStart: Int
    public let offsetEnd: Int

    public init(
        name: HeaderName,
        value: HeaderValue,
        offsetField: Int,
        offsetStart: Int,
        offsetEnd: Int
    ) {
        self.name = name
        self.value = value
        self.offsetField = offsetField
        self.offsetStart = offsetStart
        self.offsetEnd = offsetEnd
    }
}

public enum HeaderName: Sendable, Hashable {
    case subject
    case from
    case to
    case cc
    case date
    case bcc
    case replyTo
    case sender
    case comments
    case inReplyTo
    case keywords
    case received
    case messageID
    case references
    case returnPath
    case mimeVersion
    case contentDescription
    case contentID
    case contentLanguage
    case contentLocation
    case contentTransferEncoding
    case contentType
    case contentDisposition
    case resentTo
    case resentFrom
    case resentBcc
    case resentCc
    case resentSender
    case resentDate
    case resentMessageID
    case listArchive
    case listHelp
    case listID
    case listOwner
    case listPost
    case listSubscribe
    case listUnsubscribe
    case dkimSignature
    case arcAuthenticationResults
    case arcMessageSignature
    case arcSeal
    case dkim2Signature
    case messageInstance
    case other(String)

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        switch trimmed.lowercased() {
        case "subject": self = .subject
        case "from": self = .from
        case "to": self = .to
        case "cc": self = .cc
        case "date": self = .date
        case "bcc": self = .bcc
        case "reply-to": self = .replyTo
        case "sender": self = .sender
        case "comments": self = .comments
        case "in-reply-to": self = .inReplyTo
        case "keywords": self = .keywords
        case "received": self = .received
        case "message-id": self = .messageID
        case "references": self = .references
        case "return-path": self = .returnPath
        case "mime-version": self = .mimeVersion
        case "content-description": self = .contentDescription
        case "content-id": self = .contentID
        case "content-language": self = .contentLanguage
        case "content-location": self = .contentLocation
        case "content-transfer-encoding": self = .contentTransferEncoding
        case "content-type": self = .contentType
        case "content-disposition": self = .contentDisposition
        case "resent-to": self = .resentTo
        case "resent-from": self = .resentFrom
        case "resent-bcc": self = .resentBcc
        case "resent-cc": self = .resentCc
        case "resent-sender": self = .resentSender
        case "resent-date": self = .resentDate
        case "resent-message-id": self = .resentMessageID
        case "list-archive": self = .listArchive
        case "list-help": self = .listHelp
        case "list-id": self = .listID
        case "list-owner": self = .listOwner
        case "list-post": self = .listPost
        case "list-subscribe": self = .listSubscribe
        case "list-unsubscribe": self = .listUnsubscribe
        case "dkim-signature": self = .dkimSignature
        case "arc-authentication-results": self = .arcAuthenticationResults
        case "arc-message-signature": self = .arcMessageSignature
        case "arc-seal": self = .arcSeal
        case "dkim2-signature": self = .dkim2Signature
        case "message-instance": self = .messageInstance
        default: self = .other(trimmed)
        }
    }

    public var rawValue: String {
        switch self {
        case .subject: "Subject"
        case .from: "From"
        case .to: "To"
        case .cc: "Cc"
        case .date: "Date"
        case .bcc: "Bcc"
        case .replyTo: "Reply-To"
        case .sender: "Sender"
        case .comments: "Comments"
        case .inReplyTo: "In-Reply-To"
        case .keywords: "Keywords"
        case .received: "Received"
        case .messageID: "Message-ID"
        case .references: "References"
        case .returnPath: "Return-Path"
        case .mimeVersion: "MIME-Version"
        case .contentDescription: "Content-Description"
        case .contentID: "Content-ID"
        case .contentLanguage: "Content-Language"
        case .contentLocation: "Content-Location"
        case .contentTransferEncoding: "Content-Transfer-Encoding"
        case .contentType: "Content-Type"
        case .contentDisposition: "Content-Disposition"
        case .resentTo: "Resent-To"
        case .resentFrom: "Resent-From"
        case .resentBcc: "Resent-Bcc"
        case .resentCc: "Resent-Cc"
        case .resentSender: "Resent-Sender"
        case .resentDate: "Resent-Date"
        case .resentMessageID: "Resent-Message-ID"
        case .listArchive: "List-Archive"
        case .listHelp: "List-Help"
        case .listID: "List-ID"
        case .listOwner: "List-Owner"
        case .listPost: "List-Post"
        case .listSubscribe: "List-Subscribe"
        case .listUnsubscribe: "List-Unsubscribe"
        case .dkimSignature: "DKIM-Signature"
        case .arcAuthenticationResults: "ARC-Authentication-Results"
        case .arcMessageSignature: "ARC-Message-Signature"
        case .arcSeal: "ARC-Seal"
        case .dkim2Signature: "DKIM2-Signature"
        case .messageInstance: "Message-Instance"
        case .other(let name): name
        }
    }

    public static func == (lhs: HeaderName, rhs: HeaderName) -> Bool {
        switch (lhs, rhs) {
        case (.other(let lhsName), .other(let rhsName)):
            asciiFoldedHeaderName(lhsName)
                == asciiFoldedHeaderName(rhsName)
        case (.other, _), (_, .other):
            false
        default:
            lhs.rawValue == rhs.rawValue
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .other(let name):
            hasher.combine(0)
            hasher.combine(asciiFoldedHeaderName(name))
        default:
            hasher.combine(1)
            hasher.combine(rawValue)
        }
    }
}

private func asciiFoldedHeaderName(_ name: String) -> String {
    String(
        decoding: name.utf8.map { byte in
            (0x41...0x5A).contains(byte)
                ? byte + 0x20
                : byte
        },
        as: UTF8.self
    )
}

extension HeaderName: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    private enum Kind: String, Codable {
        case recognized
        case other
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)

        switch try container.decode(Kind.self, forKey: .type) {
        case .recognized:
            guard let value = HeaderName(name) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .name,
                    in: container,
                    debugDescription: "Unrecognized tagged header name"
                )
            }
            if case .other = value {
                throw DecodingError.dataCorruptedError(
                    forKey: .name,
                    in: container,
                    debugDescription: "Unrecognized tagged header name"
                )
            }
            self = value
        case .other:
            self = .other(name)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .other(let name):
            try container.encode(Kind.other, forKey: .type)
            try container.encode(name, forKey: .name)
        default:
            try container.encode(Kind.recognized, forKey: .type)
            try container.encode(rawValue, forKey: .name)
        }
    }
}

public enum HeaderValue: Sendable, Equatable {
    case address(Address)
    case text(String)
    case textList([String])
    case dateTime(MailDateTime)
    case contentType(ContentType)
    case received(Received)
    case empty

    public var text: String? {
        switch self {
        case .text(let value): value
        case .textList(let values): values.last
        default: nil
        }
    }

    public var isEmpty: Bool {
        if case .empty = self { true } else { false }
    }

    public var textValues: [String] {
        switch self {
        case .text(let value): [value]
        case .textList(let values): values
        default: []
        }
    }

    public var address: Address? {
        guard case .address(let value) = self else {
            return nil
        }

        return value
    }

    public var dateTime: MailDateTime? {
        guard case .dateTime(let value) = self else {
            return nil
        }

        return value
    }

    public var contentType: ContentType? {
        guard case .contentType(let value) = self else {
            return nil
        }

        return value
    }

    public var received: Received? {
        guard case .received(let value) = self else {
            return nil
        }

        return value
    }
}

extension HeaderValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case address
        case text
        case values
        case dateTime
        case contentType
        case received
    }

    private enum Kind: String, Codable {
        case address
        case text
        case textList
        case dateTime
        case contentType
        case received
        case empty
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .address:
            self = .address(try container.decode(Address.self, forKey: .address))
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .textList:
            self = .textList(try container.decode([String].self, forKey: .values))
        case .dateTime:
            self = .dateTime(try container.decode(MailDateTime.self, forKey: .dateTime))
        case .contentType:
            self = .contentType(try container.decode(ContentType.self, forKey: .contentType))
        case .received:
            self = .received(try container.decode(Received.self, forKey: .received))
        case .empty:
            self = .empty
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .address(let value):
            try container.encode(Kind.address, forKey: .type)
            try container.encode(value, forKey: .address)
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .textList(let values):
            try container.encode(Kind.textList, forKey: .type)
            try container.encode(values, forKey: .values)
        case .dateTime(let value):
            try container.encode(Kind.dateTime, forKey: .type)
            try container.encode(value, forKey: .dateTime)
        case .contentType(let value):
            try container.encode(Kind.contentType, forKey: .type)
            try container.encode(value, forKey: .contentType)
        case .received(let value):
            try container.encode(Kind.received, forKey: .type)
            try container.encode(value, forKey: .received)
        case .empty:
            try container.encode(Kind.empty, forKey: .type)
        }
    }
}

public enum Address: Sendable, Equatable {
    case list([MailAddress])
    case group([AddressGroup])

    public var flattened: [MailAddress] {
        switch self {
        case .list(let addresses): addresses
        case .group(let groups): groups.flatMap(\.addresses)
        }
    }

    public var first: MailAddress? {
        flattened.first
    }
}

extension Address: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case addresses
        case groups
    }

    private enum Kind: String, Codable {
        case list
        case group
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .list:
            self = .list(try container.decode([MailAddress].self, forKey: .addresses))
        case .group:
            self = .group(try container.decode([AddressGroup].self, forKey: .groups))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .list(let value):
            try container.encode(Kind.list, forKey: .type)
            try container.encode(value, forKey: .addresses)
        case .group(let value):
            try container.encode(Kind.group, forKey: .type)
            try container.encode(value, forKey: .groups)
        }
    }
}

public struct MailAddress: Sendable, Equatable, Codable {
    public let name: String?
    public let address: String?

    public init(name: String?, address: String?) {
        self.name = name
        self.address = address
    }
}

public struct AddressGroup: Sendable, Equatable, Codable {
    public let name: String?
    public let addresses: [MailAddress]

    public init(name: String?, addresses: [MailAddress]) {
        self.name = name
        self.addresses = addresses
    }
}

public struct ContentType: Sendable, Equatable, Codable {
    public let type: String
    public let subtype: String?
    public let attributes: [MIMEAttribute]

    public init(
        type: String,
        subtype: String?,
        attributes: [MIMEAttribute] = []
    ) {
        self.type = type
        self.subtype = subtype
        self.attributes = attributes
    }

    public func attribute(named name: String) -> String? {
        attributes.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    public var isAttachment: Bool {
        type.caseInsensitiveCompare("attachment") == .orderedSame
    }

    public var isInline: Bool {
        type.caseInsensitiveCompare("inline") == .orderedSame
    }
}

public struct MIMEAttribute: Sendable, Equatable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MailDateTime: Sendable, Equatable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let isNegativeOffset: Bool
    public let offsetHour: Int
    public let offsetMinute: Int

    public init(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        isNegativeOffset: Bool,
        offsetHour: Int,
        offsetMinute: Int
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.isNegativeOffset = isNegativeOffset
        self.offsetHour = offsetHour
        self.offsetMinute = offsetMinute
    }

    public var offsetSeconds: Int {
        guard (0...23).contains(offsetHour), (0...59).contains(offsetMinute) else {
            return 0
        }
        let seconds = (offsetHour * 60 + offsetMinute) * 60
        return isNegativeOffset ? -seconds : seconds
    }

    public var foundationDate: Date? {
        guard isValid else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(exactTimestamp))
    }

    public var timestamp: Int64? {
        isValid ? exactTimestamp : nil
    }

    public var rfc3339: String {
        if offsetHour == 0, offsetMinute == 0 {
            return String(
                format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
                year,
                month,
                day,
                hour,
                minute,
                second
            )
        }
        let sign = isNegativeOffset ? "-" : "+"

        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d%@%02d:%02d",
            year,
            month,
            day,
            hour,
            minute,
            second,
            sign,
            offsetHour,
            offsetMinute
        )
    }
}

public struct Received: Sendable, Equatable, Codable {
    public let from: Host?
    public let fromIP: String?
    public let fromIPReverse: String?
    public let by: Host?
    public let forRecipient: String?
    public let protocolValue: MailProtocol?
    public let tlsVersion: TLSVersion?
    public let tlsCipher: String?
    public let id: String?
    public let ident: String?
    public let helo: Host?
    public let heloCommand: Greeting?
    public let via: String?
    public let date: MailDateTime?

    public init(
        from: Host? = nil,
        fromIP: String? = nil,
        fromIPReverse: String? = nil,
        by: Host? = nil,
        forRecipient: String? = nil,
        protocolValue: MailProtocol? = nil,
        tlsVersion: TLSVersion? = nil,
        tlsCipher: String? = nil,
        id: String? = nil,
        ident: String? = nil,
        helo: Host? = nil,
        heloCommand: Greeting? = nil,
        via: String? = nil,
        date: MailDateTime? = nil
    ) {
        self.from = from
        self.fromIP = fromIP
        self.fromIPReverse = fromIPReverse
        self.by = by
        self.forRecipient = forRecipient
        self.protocolValue = protocolValue
        self.tlsVersion = tlsVersion
        self.tlsCipher = tlsCipher
        self.id = id
        self.ident = ident
        self.helo = helo
        self.heloCommand = heloCommand
        self.via = via
        self.date = date
    }
}

public enum Host: Sendable, Equatable {
    case name(String)
    case ipAddress(String)
}

extension Host: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Kind: String, Codable {
        case name
        case ipAddress
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)

        switch try container.decode(Kind.self, forKey: .type) {
        case .name: self = .name(value)
        case .ipAddress: self = .ipAddress(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .name(let value):
            try container.encode(Kind.name, forKey: .type)
            try container.encode(value, forKey: .value)
        case .ipAddress(let value):
            try container.encode(Kind.ipAddress, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum TLSVersion: String, Sendable, Equatable, Codable {
    case ssl2
    case ssl3
    case tls1_0
    case tls1_1
    case tls1_2
    case tls1_3
    case dtls1_0
    case dtls1_2
    case dtls1_3
}

public enum Greeting: String, Sendable, Equatable, Codable {
    case helo
    case ehlo
    case lhlo
}

public enum MailProtocol: String, Sendable, Equatable, Codable {
    case smtp
    case esmtp
    case esmtpa
    case esmtps
    case esmtpsa
    case lmtp
    case lmtpa
    case lmtps
    case lmtpsa
    case mms
    case utf8smtp
    case utf8smtpa
    case utf8smtps
    case utf8smtpsa
    case utf8lmtp
    case utf8lmtpa
    case utf8lmtps
    case utf8lmtpsa
    case http
    case https
    case imap
    case pop3
    case local
}
