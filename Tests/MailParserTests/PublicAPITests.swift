import Foundation
import Testing
@testable import MailParser

@Test
func fixedHeaderConveniencesUseLastOccurrenceAndExposeAllValues() throws {
    let firstDate = MailDateTime(
        year: 2026,
        month: 8,
        day: 18,
        hour: 10,
        minute: 0,
        second: 0,
        isNegativeOffset: false,
        offsetHour: 0,
        offsetMinute: 0
    )
    let secondDate = MailDateTime(
        year: 2026,
        month: 8,
        day: 19,
        hour: 11,
        minute: 0,
        second: 0,
        isNegativeOffset: true,
        offsetHour: 4,
        offsetMinute: 0
    )
    let firstAddress = Address.list([
        MailAddress(name: "First", address: "first@example.com")
    ])
    let secondAddress = Address.list([
        MailAddress(name: "Second", address: "second@example.com")
    ])
    let listAddress = Address.list([
        MailAddress(name: nil, address: "mailto:list@example.com")
    ])
    let received = Received(id: "received-id", date: secondDate)
    let contentType = ContentType(type: "text", subtype: "plain")

    var headers: [Header] = []
    func append(_ name: HeaderName, _ value: HeaderValue) {
        headers.append(
            Header(
                name: name,
                value: value,
                offsetField: 0,
                offsetStart: 0,
                offsetEnd: 0
            )
        )
    }

    append(.subject, .text("Re: [list] Topic"))
    append(.messageID, .textList(["first-id", "second-id"]))
    append(.messageID, .text("last-id"))
    append(.inReplyTo, .text("reply-one"))
    append(.inReplyTo, .textList(["reply-two", "reply-three"]))
    append(.references, .textList(["reference-one", "reference-two"]))
    append(.resentMessageID, .textList(["resent-one", "resent-two"]))
    append(.returnPath, .text("bounce@example.com"))
    append(.contentID, .textList(["content-one", "content-two"]))
    append(.from, .address(firstAddress))
    append(.from, .address(secondAddress))
    append(.to, .address(firstAddress))
    append(.cc, .address(firstAddress))
    append(.bcc, .address(firstAddress))
    append(.replyTo, .address(firstAddress))
    append(.sender, .address(firstAddress))
    append(.resentFrom, .address(secondAddress))
    append(.resentTo, .address(secondAddress))
    append(.resentCc, .address(secondAddress))
    append(.resentBcc, .address(secondAddress))
    append(.resentSender, .address(secondAddress))
    append(.date, .dateTime(firstDate))
    append(.date, .dateTime(secondDate))
    append(.resentDate, .dateTime(firstDate))
    append(.resentDate, .dateTime(secondDate))
    append(.comments, .text("comment"))
    append(.keywords, .textList(["swift", "mime"]))
    append(.listArchive, .address(listAddress))
    append(.listHelp, .address(listAddress))
    append(.listID, .address(listAddress))
    append(.listOwner, .address(listAddress))
    append(.listPost, .address(listAddress))
    append(.listSubscribe, .address(listAddress))
    append(.listUnsubscribe, .address(listAddress))
    append(.mimeVersion, .text("1.0"))
    append(.contentType, .contentType(contentType))
    append(.contentDisposition, .contentType(ContentType(type: "inline", subtype: nil)))
    append(.contentDescription, .text("description"))
    append(.contentLanguage, .textList(["en", "fr"]))
    append(.contentLocation, .text("https://example.com/body"))
    append(.contentTransferEncoding, .text("quoted-printable"))
    append(.received, .received(received))

    let root = MessagePart(
        headers: headers,
        isEncodingProblem: false,
        body: .multipart([1, 2, 3]),
        encoding: .none,
        offsetHeader: 0,
        offsetBody: 0,
        offsetEnd: 0
    )
    let text = MessagePart(
        headers: [],
        isEncodingProblem: false,
        body: .text("Text"),
        encoding: .none,
        offsetHeader: 0,
        offsetBody: 0,
        offsetEnd: 4
    )
    let html = MessagePart(
        headers: [],
        isEncodingProblem: false,
        body: .html("<p>HTML</p>"),
        encoding: .none,
        offsetHeader: 0,
        offsetBody: 0,
        offsetEnd: 11
    )
    let attachment = MessagePart(
        headers: [
            Header(
                name: .contentDisposition,
                value: .contentType(
                    ContentType(
                        type: "attachment",
                        subtype: nil,
                        attributes: [MIMEAttribute(name: "filename", value: "file.bin")]
                    )
                ),
                offsetField: 0,
                offsetStart: 0,
                offsetEnd: 0
            )
        ],
        isEncodingProblem: false,
        body: .binary(Data([0, 1, 2])),
        encoding: .base64,
        offsetHeader: 0,
        offsetBody: 0,
        offsetEnd: 3
    )
    let message = Message(
        htmlBody: [2],
        textBody: [1],
        attachments: [3],
        parts: [root, text, html, attachment],
        rawMessage: Data()
    )

    #expect(message.subject == "Re: [list] Topic")
    #expect(message.baseSubject == "Topic")
    #expect(message.messageID == "last-id")
    #expect(message.messageIDs == ["first-id", "second-id", "last-id"])
    #expect(message.inReplyToID == "reply-three")
    #expect(message.inReplyToIDs == ["reply-one", "reply-two", "reply-three"])
    #expect(message.referenceID == "reference-two")
    #expect(message.referenceIDs == ["reference-one", "reference-two"])
    #expect(message.resentMessageID == "resent-two")
    #expect(message.resentMessageIDs == ["resent-one", "resent-two"])
    #expect(message.returnPathIDs == ["bounce@example.com"])
    #expect(message.contentID == "content-two")
    #expect(message.contentIDs == ["content-one", "content-two"])
    #expect(message.returnAddress == "bounce@example.com")
    #expect(message.from == secondAddress)
    #expect(message.allFrom == [firstAddress, secondAddress])
    #expect(message.allTo == [firstAddress])
    #expect(message.allCc == [firstAddress])
    #expect(message.allBcc == [firstAddress])
    #expect(message.allReplyTo == [firstAddress])
    #expect(message.allSender == [firstAddress])
    #expect(message.resentFrom == secondAddress)
    #expect(message.resentTo == secondAddress)
    #expect(message.resentCc == secondAddress)
    #expect(message.resentBcc == secondAddress)
    #expect(message.resentSender == secondAddress)
    #expect(message.date == secondDate)
    #expect(message.dates == [firstDate, secondDate])
    #expect(message.resentDate == secondDate)
    #expect(message.resentDates == [firstDate, secondDate])
    #expect(message.comments == "comment")
    #expect(message.keywords == ["swift", "mime"])
    #expect(message.listArchive == listAddress)
    #expect(message.listHelp == listAddress)
    #expect(message.listID == listAddress)
    #expect(message.listOwner == listAddress)
    #expect(message.listPost == listAddress)
    #expect(message.listSubscribe == listAddress)
    #expect(message.listUnsubscribe == listAddress)
    #expect(message.mimeVersion == "1.0")
    #expect(message.contentType == contentType)
    #expect(message.contentDisposition?.isInline == true)
    #expect(message.contentDescription == "description")
    #expect(message.contentLanguage == ["en", "fr"])
    #expect(message.contentLocation == "https://example.com/body")
    #expect(message.contentTransferEncoding == "quoted-printable")
    #expect(message.received == received)
    #expect(message.receivedAll == [received])
    #expect(message.textBodyCount == 1)
    #expect(message.htmlBodyCount == 1)
    #expect(message.attachmentCount == 1)
    #expect(message.textParts == [text])
    #expect(message.htmlParts == [html])
    #expect(message.attachmentParts == [attachment])
    #expect(message.attachmentNames == ["file.bin"])
}

@Test
func rawAndPartHeaderConveniencesPreserveRepeatedOrder() {
    let raw = Data(" First\n Second\n".utf8)
    let first = Header(
        name: .subject,
        value: .text("First"),
        offsetField: 0,
        offsetStart: 0,
        offsetEnd: 7
    )
    let second = Header(
        name: .subject,
        value: .text("Second"),
        offsetField: 7,
        offsetStart: 7,
        offsetEnd: raw.count
    )
    let root = MessagePart(
        headers: [first, second],
        isEncodingProblem: false,
        body: .text(""),
        encoding: .none,
        offsetHeader: 0,
        offsetBody: raw.count,
        offsetEnd: raw.count
    )
    let message = Message(
        htmlBody: [],
        textBody: [0],
        attachments: [],
        parts: [root],
        rawMessage: raw
    )

    #expect(message.rawHeader(.subject) == " Second")
    #expect(message.rawHeaderValues(named: "SUBJECT") == [" First", " Second"])
    #expect(root.header(named: "subject") == .text("Second"))
    #expect(root.headerValues(.subject) == [.text("First"), .text("Second")])
    #expect(HeaderValue.textList(["one", "two"]).text == "two")
}

@Test
func publicStoredModelsConformAndAssociatedEnumsUseTaggedCodable() throws {
    func requireValueSemantics<T: Sendable & Equatable & Codable>(_: T) {}

    let date = MailDateTime(
        year: 2026,
        month: 8,
        day: 19,
        hour: 12,
        minute: 0,
        second: 0,
        isNegativeOffset: false,
        offsetHour: 0,
        offsetMinute: 0
    )
    requireValueSemantics(MailAddress(name: nil, address: nil))
    requireValueSemantics(AddressGroup(name: nil, addresses: []))
    requireValueSemantics(MIMEAttribute(name: "charset", value: "utf-8"))
    requireValueSemantics(ContentType(type: "text", subtype: "plain"))
    requireValueSemantics(date)
    requireValueSemantics(Received(date: date))
    requireValueSemantics(HeaderName.other("X-Test"))
    requireValueSemantics(HeaderValue.textList(["one", "two"]))
    requireValueSemantics(Address.group([]))
    requireValueSemantics(Host.name("mx.example.com"))
    requireValueSemantics(TransferEncoding.base64)
    requireValueSemantics(TLSVersion.tls1_3)
    requireValueSemantics(Greeting.ehlo)
    requireValueSemantics(MailProtocol.esmtps)
    requireValueSemantics(PartBody.message(
        Message(htmlBody: [], textBody: [], attachments: [], parts: [], rawMessage: Data())
    ))

    #expect(HeaderName.other("X-Test") == .other("x-test"))
    #expect(HeaderName.other("Subject") != .subject)
    #expect(HeaderName.other("ß") != .other("SS"))
    #expect(
        Set([HeaderName.other("X-Test"), .other("x-test")])
            .count == 1
    )
    let otherNameData = try JSONEncoder().encode(HeaderName.other("Subject"))
    let decodedOtherName = try JSONDecoder().decode(HeaderName.self, from: otherNameData)
    guard case .other(let decodedName) = decodedOtherName else {
        Issue.record("Tagged HeaderName decoding must preserve the other case")
        return
    }
    #expect(decodedName == "Subject")

    for value in [
        otherNameData,
        try JSONEncoder().encode(HeaderValue.text("value")),
        try JSONEncoder().encode(Address.list([])),
        try JSONEncoder().encode(Host.ipAddress("192.0.2.1")),
        try JSONEncoder().encode(PartBody.binary(Data([0, 1]))),
    ] {
        let object = try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
        #expect(object["type"] != nil)
    }
}

@Test
func mailDateTimeAccessorsRejectExtremeCallerValuesWithoutTrapping() throws {
    let valid = MailDateTime(
        year: 2026,
        month: 8,
        day: 19,
        hour: 12,
        minute: 0,
        second: 0,
        isNegativeOffset: false,
        offsetHour: 0,
        offsetMinute: 0
    )
    #expect(valid.converted(toOffset: -4 * 3_600)?.offsetSeconds == -14_400)
    #expect(valid.converted(toOffset: Int64.min) == nil)
    #expect(valid.converted(toOffset: Int64.max) == nil)

    let extreme = MailDateTime(
        year: Int.max,
        month: Int.min,
        day: Int.max,
        hour: Int.min,
        minute: Int.max,
        second: Int.min,
        isNegativeOffset: true,
        offsetHour: Int.max,
        offsetMinute: Int.min
    )
    #expect(!extreme.isValid)
    #expect(extreme.offsetSeconds == 0)
    #expect(extreme.timestamp == nil)
    #expect(extreme.foundationDate == nil)
    #expect(extreme.exactTimestamp == 0)
    #expect(extreme.localTimestamp == 0)
    #expect(extreme.julianDay == 0)
    #expect(!extreme.rfc3339.isEmpty)
    #expect(!extreme.rfc5322.isEmpty)
    #expect((0...6).contains(extreme.dayOfWeek))
    #expect(extreme.converted(toOffset: 0) == nil)

    #expect(!MailDateTime.fromTimestamp(.min).isValid)
    #expect(!MailDateTime.fromTimestamp(.max).isValid)
}

@Test
func messagePartLengthRejectsOverflowingDecodedOffsets() {
    let part = MessagePart(
        headers: [],
        isEncodingProblem: true,
        body: .binary(Data()),
        encoding: .none,
        offsetHeader: .min,
        offsetBody: 0,
        offsetEnd: .max
    )

    #expect(part.rawLength == 0)
}
