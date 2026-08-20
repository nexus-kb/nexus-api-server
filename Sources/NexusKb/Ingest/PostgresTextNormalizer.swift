import Foundation

enum PostgresTextNormalizer {
    static func normalize(
        _ value: String
    ) -> String {
        value.replacingOccurrences(
            of: "\u{0000}",
            with: "\\0"
        )
    }

    static func normalize(
        _ parsed: ParsedIngestMessage
    ) -> ParsedIngestMessage {
        ParsedIngestMessage(
            message: normalize(
                parsed.message
            ),
            messageIDAliases:
                parsed.messageIDAliases.map {
                    normalize($0)
                },
            author: normalize(
                parsed.author
            ),
            patch: ParsedPatchMetadata(
                partIndex:
                    parsed.patch.partIndex,
                totalParts:
                    parsed.patch.totalParts,
                version:
                    parsed.patch.version,
                isPatchOrCover:
                    parsed.patch.isPatchOrCover,
                diff: parsed.patch.diff.map {
                    normalize($0)
                }
            )
        )
    }

    private static func normalize(
        _ message: IngestMailMessage
    ) -> IngestMailMessage {
        IngestMailMessage(
            messageID: normalize(
                message.messageID
            ),
            subject: normalize(
                message.subject
            ),
            from: message.from.map {
                normalize($0)
            },
            to: message.to.map {
                normalize($0)
            },
            cc: message.cc.map {
                normalize($0)
            },
            date: message.date,
            inReplyTo: message.inReplyTo.map {
                normalize($0)
            },
            references:
                message.references.map {
                    normalize($0)
                },
            textBody: normalize(
                message.textBody
            )
        )
    }

    private static func normalize(
        _ mailbox: IngestMailbox
    ) -> IngestMailbox {
        IngestMailbox(
            name: mailbox.name.map {
                normalize($0)
            },
            address: normalize(
                mailbox.address
            )
        )
    }
}
