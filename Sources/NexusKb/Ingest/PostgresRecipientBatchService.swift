import PostgresNIO
import Vapor

enum PostgresRecipientBatchError:
    Error,
    Sendable,
    Equatable
{
    case invalidRecipientOrdinal(Int64)
    case missingPersonResolution(Int)
}

struct ResolvedBatchRecipient:
    Sendable,
    Hashable
{
    let personID: Int64
    let recipientType: String
}

struct ResolvedBatchRecipients: Sendable {
    private let recipientsByMessageIndex: [[ResolvedBatchRecipient]]

    init(
        recipientsByMessageIndex:
            [[ResolvedBatchRecipient]]
    ) {
        self.recipientsByMessageIndex =
            recipientsByMessageIndex
    }

    func recipients(
        forMessageAt index: Int
    ) -> [ResolvedBatchRecipient] {
        recipientsByMessageIndex[index]
    }
}

struct PostgresRecipientBatchService: Sendable {
    private struct UnresolvedRecipient:
        Sendable
    {
        let messageIndex: Int
        let email: String
        let name: String?
        let recipientType: String
    }

    func resolvePeople(
        messages: [ParsedIngestMessage],
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> ResolvedBatchRecipients {
        var unresolved: [UnresolvedRecipient] = []

        for (
            messageIndex,
            parsed
        ) in messages.enumerated() {
            unresolved.append(
                contentsOf:
                    parsed.message.to.map {
                        UnresolvedRecipient(
                            messageIndex:
                                messageIndex,
                            email: $0.address,
                            name: $0.name,
                            recipientType:
                                RecipientType
                                .to
                                .rawValue
                        )
                    }
            )

            unresolved.append(
                contentsOf:
                    parsed.message.cc.map {
                        UnresolvedRecipient(
                            messageIndex:
                                messageIndex,
                            email: $0.address,
                            name: $0.name,
                            recipientType:
                                RecipientType
                                .cc
                                .rawValue
                        )
                    }
            )
        }

        guard !unresolved.isEmpty else {
            return ResolvedBatchRecipients(
                recipientsByMessageIndex:
                    Array(
                        repeating: [],
                        count: messages.count
                    )
            )
        }

        let emails = unresolved.map(\.email)
        let names = unresolved.map {
            $0.name ?? ""
        }
        let hasNames = unresolved.map {
            $0.name != nil
        }

        let rows = try await connection.query(
            """
            WITH recipient_input AS (
                SELECT
                    input.email,
                    CASE
                        WHEN input.has_name
                        THEN input.name
                        ELSE NULL
                    END AS name,
                    input.ordinality
                FROM unnest(
                    \(emails)::text[],
                    \(names)::text[],
                    \(hasNames)::boolean[]
                ) WITH ORDINALITY
                  AS input(
                      email,
                      name,
                      has_name,
                      ordinality
                  )
            ),
            people_to_upsert AS (
                SELECT
                    lower(email) AS email_key,
                    (
                        array_agg(
                            email
                            ORDER BY ordinality
                        )
                    )[1] AS email,
                    (
                        array_agg(
                            name
                            ORDER BY ordinality DESC
                        )
                        FILTER (
                            WHERE name IS NOT NULL
                        )
                    )[1] AS name
                FROM recipient_input
                GROUP BY lower(email)
            ),
            upserted_people AS (
                INSERT INTO people (
                    name,
                    email
                )
                SELECT
                    name,
                    email
                FROM people_to_upsert
                ORDER BY email_key
                ON CONFLICT (
                    lower(email)
                ) DO UPDATE
                SET name = COALESCE(
                    EXCLUDED.name,
                    people.name
                )
                RETURNING
                    id,
                    lower(email) AS email_key
            )
            SELECT
                input.ordinality,
                person.id
            FROM recipient_input AS input
            JOIN upserted_people AS person
              ON person.email_key =
                    lower(input.email)
            ORDER BY input.ordinality
            """,
            logger: logger
        )

        var resolvedByOrdinal =
            [ResolvedBatchRecipient?](
                repeating: nil,
                count: unresolved.count
            )

        for try await row in rows {
            let value = try row.decode(
                (Int64, Int64).self
            )

            let ordinal = value.0
            let index = Int(ordinal - 1)

            guard
                resolvedByOrdinal.indices
                    .contains(index)
            else {
                throw
                    PostgresRecipientBatchError
                    .invalidRecipientOrdinal(
                        ordinal
                    )
            }

            resolvedByOrdinal[index] =
                ResolvedBatchRecipient(
                    personID: value.1,
                    recipientType:
                        unresolved[index]
                        .recipientType
                )
        }

        var recipientsByMessageIndex =
            [[ResolvedBatchRecipient]](
                repeating: [],
                count: messages.count
            )

        var seenByMessageIndex =
            [Set<ResolvedBatchRecipient>](
                repeating: [],
                count: messages.count
            )

        for index in unresolved.indices {
            guard
                let recipient =
                    resolvedByOrdinal[index]
            else {
                throw
                    PostgresRecipientBatchError
                    .missingPersonResolution(
                        index
                    )
            }

            let messageIndex =
                unresolved[index].messageIndex

            guard
                seenByMessageIndex[
                    messageIndex
                ].insert(recipient).inserted
            else {
                continue
            }

            recipientsByMessageIndex[
                messageIndex
            ].append(recipient)
        }

        return ResolvedBatchRecipients(
            recipientsByMessageIndex:
                recipientsByMessageIndex
        )
    }

    func replaceRecipients(
        recipientsByMessageID:
            [Int64: [ResolvedBatchRecipient]],
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let messageIDs =
            recipientsByMessageID
            .keys
            .sorted()

        guard !messageIDs.isEmpty else {
            return
        }

        try await execute(
            """
            DELETE FROM messages_recipients
            WHERE message_id =
                ANY(\(messageIDs)::bigint[])
            """,
            on: connection,
            logger: logger
        )

        var linkMessageIDs: [Int64] = []
        var linkPersonIDs: [Int64] = []
        var linkRecipientTypes: [String] = []

        for messageID in messageIDs {
            let recipients =
                recipientsByMessageID[
                    messageID,
                    default: []
                ]
                .sorted {
                    if $0.personID != $1.personID {
                        return $0.personID
                            < $1.personID
                    }

                    return $0.recipientType
                        < $1.recipientType
                }

            for recipient in recipients {
                linkMessageIDs.append(
                    messageID
                )
                linkPersonIDs.append(
                    recipient.personID
                )
                linkRecipientTypes.append(
                    recipient.recipientType
                )
            }
        }

        guard !linkMessageIDs.isEmpty else {
            return
        }

        try await execute(
            """
            INSERT INTO messages_recipients (
                message_id,
                person_id,
                recipient_type
            )
            SELECT
                input.message_id,
                input.person_id,
                input.recipient_type
            FROM unnest(
                \(linkMessageIDs)::bigint[],
                \(linkPersonIDs)::bigint[],
                \(linkRecipientTypes)::text[]
            ) AS input(
                message_id,
                person_id,
                recipient_type
            )
            ON CONFLICT DO NOTHING
            """,
            on: connection,
            logger: logger
        )
    }

    private func execute(
        _ query: PostgresQuery,
        on connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let rows = try await connection.query(
            query,
            logger: logger
        )

        for try await _ in rows {}
    }
}
