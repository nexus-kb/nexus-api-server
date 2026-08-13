//
//  MailMessage.swift
//  MailParser
//
//  Created by Tanuj Ravi Rao on 8/12/26.
//

import Foundation

public struct Mailbox: Sendable, Equatable, Hashable {
    public let name: String?
    public let address: String

    public init(name: String?, address: String) {
        self.name = name
        self.address = address
    }

    public var displayString: String {
        guard let name, !name.isEmpty else {
            return address
        }

        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escapedName)\" <\(address)>"
    }
}

public struct MailMessage: Sendable, Equatable {
    public let headers: MailHeaders
    public let messageID: String
    public let subject: String
    public let from: Mailbox?
    public let to: [Mailbox]
    public let cc: [Mailbox]
    public let date: Date?
    public let receivedDate: Date?
    public let inReplyTo: String?
    public let references: [String]
    public let textBody: String

    public init(
        headers: MailHeaders,
        messageID: String,
        subject: String,
        from: Mailbox?,
        to: [Mailbox],
        cc: [Mailbox],
        date: Date?,
        receivedDate: Date?,
        inReplyTo: String?,
        references: [String],
        textBody: String
    ) {
        self.headers = headers
        self.messageID = messageID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.receivedDate = receivedDate
        self.inReplyTo = inReplyTo
        self.references = references
        self.textBody = textBody
    }
}

public enum MailParserError: Error, Sendable, Equatable {
    case emptyMessage
    case malformedHeader(String)
    case missingMessageID
    case malformedMultipartBoundary
    case invalidBase64Body
}
