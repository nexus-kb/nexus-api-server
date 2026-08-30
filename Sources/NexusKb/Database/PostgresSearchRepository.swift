import PostgresNIO
import Vapor

struct PostgresSearchRepository: Sendable {
    let client: PostgresClient

    func search(
        scope: MailSearchScope,
        offset: Int,
        logger: Logger
    ) async throws -> MailSearchPageResult {
        let fetchLimit = scope.limit + 1
        let rows: PostgresRowSequence
        let hasMetadataFilter =
            scope.filter.author != nil
            || scope.filter.sentAtLowerBound != nil
            || scope.filter.sentAtUpperBound != nil
            || scope.mailingList != nil

        if let text = scope.filter.text,
           !hasMetadataFilter
        {
            rows = try await client.query(
                """
                WITH ranked AS MATERIALIZED (
                    SELECT
                        document.thread_id,
                        pdb.score(document.thread_id)::double precision
                            AS score,
                        COALESCE(
                            NULLIF(
                                pdb.snippet(
                                    document.content,
                                    start_tag => '[',
                                    end_tag => ']',
                                    max_num_chars => 320
                                ),
                                ''
                            ),
                            NULLIF(document.subject, ''),
                            left(document.content, 320)
                        ) AS snippet
                    FROM thread_search_documents AS document
                    WHERE document.thread_id @@@ pdb.parse(
                        \(text),
                        lenient => true,
                        conjunction_mode => true
                    )
                      AND (
                        \(scope.filter.subject == nil)
                        OR document.subject @@@
                            pdb.parse_with_field(
                                \(scope.filter.subject),
                                lenient => true,
                                conjunction_mode => true
                            )
                      )
                    ORDER BY
                        pdb.score(document.thread_id) DESC,
                        document.thread_id ASC
                    LIMIT \(fetchLimit)
                    OFFSET \(offset)
                )
                SELECT
                    ranked.thread_id,
                    thread.root_message_id,
                    ranked.score,
                    ranked.snippet
                FROM ranked
                JOIN threads AS thread
                  ON thread.id = ranked.thread_id
                ORDER BY
                    ranked.score DESC,
                    ranked.thread_id ASC
                """,
                logger: logger
            )
        } else if let text = scope.filter.text {
            rows = try await client.query(
                """
                SELECT
                    document.thread_id,
                    thread.root_message_id,
                    pdb.score(document.thread_id)::double precision,
                    COALESCE(
                        NULLIF(
                            pdb.snippet(
                                document.content,
                                start_tag => '[',
                                end_tag => ']',
                                max_num_chars => 320
                            ),
                            ''
                        ),
                        NULLIF(document.subject, ''),
                        left(document.content, 320)
                    )
                FROM thread_search_documents AS document
                JOIN threads AS thread
                  ON thread.id = document.thread_id
                JOIN messages AS root
                  ON root.message_id = thread.root_message_id
                 AND NOT root.is_placeholder
                WHERE document.thread_id @@@ pdb.parse(
                    \(text),
                    lenient => true,
                    conjunction_mode => true
                )
                  AND (
                    \(scope.filter.subject == nil)
                    OR document.subject @@@
                        pdb.parse_with_field(
                            \(scope.filter.subject),
                            lenient => true,
                            conjunction_mode => true
                        )
                  )
                  AND (
                    \(scope.filter.author == nil)
                    OR root.author_search
                        @@ plainto_tsquery(
                            'simple',
                            \(scope.filter.author)
                        )
                  )
                  AND (
                    \(scope.filter.sentAtLowerBound == nil)
                    OR root.sent_at >=
                        \(scope.filter.sentAtLowerBound)
                  )
                  AND (
                    \(scope.filter.sentAtUpperBound == nil)
                    OR root.sent_at <
                        \(scope.filter.sentAtUpperBound)
                  )
                  AND (
                    \(scope.mailingList == nil)
                    OR EXISTS (
                        SELECT 1
                        FROM messages AS member
                        JOIN messages_mailing_lists AS filter_link
                          ON filter_link.message_id = member.id
                        JOIN mailing_lists AS filter_list
                          ON filter_list.id =
                                filter_link.mailing_list_id
                        WHERE member.thread_id = thread.id
                          AND filter_list.archive_group =
                                \(scope.mailingList)
                    )
                  )
                ORDER BY
                    pdb.score(document.thread_id) DESC,
                    document.thread_id ASC
                LIMIT \(fetchLimit)
                OFFSET \(offset)
                """,
                logger: logger
            )
        } else if let subject = scope.filter.subject,
                  !hasMetadataFilter
        {
            rows = try await client.query(
                """
                WITH ranked AS MATERIALIZED (
                    SELECT
                        document.thread_id,
                        pdb.score(document.thread_id)::double precision
                            AS score,
                        COALESCE(
                            NULLIF(document.subject, ''),
                            left(document.content, 320)
                        ) AS snippet
                    FROM thread_search_documents AS document
                    WHERE document.subject @@@
                        pdb.parse_with_field(
                            \(subject),
                            lenient => true,
                            conjunction_mode => true
                        )
                    ORDER BY
                        pdb.score(document.thread_id) DESC,
                        document.thread_id ASC
                    LIMIT \(fetchLimit)
                    OFFSET \(offset)
                )
                SELECT
                    ranked.thread_id,
                    thread.root_message_id,
                    ranked.score,
                    ranked.snippet
                FROM ranked
                JOIN threads AS thread
                  ON thread.id = ranked.thread_id
                ORDER BY
                    ranked.score DESC,
                    ranked.thread_id ASC
                """,
                logger: logger
            )
        } else if let subject = scope.filter.subject {
            rows = try await client.query(
                """
                SELECT
                    document.thread_id,
                    thread.root_message_id,
                    pdb.score(document.thread_id)::double precision,
                    COALESCE(
                        NULLIF(document.subject, ''),
                        left(document.content, 320)
                    )
                FROM thread_search_documents AS document
                JOIN threads AS thread
                  ON thread.id = document.thread_id
                JOIN messages AS root
                  ON root.message_id = thread.root_message_id
                 AND NOT root.is_placeholder
                WHERE document.subject @@@
                    pdb.parse_with_field(
                        \(subject),
                        lenient => true,
                        conjunction_mode => true
                    )
                  AND (
                    \(scope.filter.author == nil)
                    OR root.author_search
                        @@ plainto_tsquery(
                            'simple',
                            \(scope.filter.author)
                        )
                  )
                  AND (
                    \(scope.filter.sentAtLowerBound == nil)
                    OR root.sent_at >=
                        \(scope.filter.sentAtLowerBound)
                  )
                  AND (
                    \(scope.filter.sentAtUpperBound == nil)
                    OR root.sent_at <
                        \(scope.filter.sentAtUpperBound)
                  )
                  AND (
                    \(scope.mailingList == nil)
                    OR EXISTS (
                        SELECT 1
                        FROM messages AS member
                        JOIN messages_mailing_lists AS filter_link
                          ON filter_link.message_id = member.id
                        JOIN mailing_lists AS filter_list
                          ON filter_list.id =
                                filter_link.mailing_list_id
                        WHERE member.thread_id = thread.id
                          AND filter_list.archive_group =
                                \(scope.mailingList)
                    )
                  )
                ORDER BY
                    pdb.score(document.thread_id) DESC,
                    document.thread_id ASC
                LIMIT \(fetchLimit)
                OFFSET \(offset)
                """,
                logger: logger
            )
        } else {
            rows = try await client.query(
                """
                SELECT
                    document.thread_id,
                    thread.root_message_id,
                    0::double precision,
                    COALESCE(
                        NULLIF(document.subject, ''),
                        left(document.content, 320)
                    )
                FROM thread_search_documents AS document
                JOIN threads AS thread
                  ON thread.id = document.thread_id
                JOIN messages AS root
                  ON root.message_id = thread.root_message_id
                 AND NOT root.is_placeholder
                WHERE (
                    \(scope.filter.author == nil)
                    OR root.author_search
                        @@ plainto_tsquery(
                            'simple',
                            \(scope.filter.author)
                        )
                  )
                  AND (
                    \(scope.filter.sentAtLowerBound == nil)
                    OR root.sent_at >=
                        \(scope.filter.sentAtLowerBound)
                  )
                  AND (
                    \(scope.filter.sentAtUpperBound == nil)
                    OR root.sent_at <
                        \(scope.filter.sentAtUpperBound)
                  )
                  AND (
                    \(scope.mailingList == nil)
                    OR EXISTS (
                        SELECT 1
                        FROM messages AS member
                        JOIN messages_mailing_lists AS filter_link
                          ON filter_link.message_id = member.id
                        JOIN mailing_lists AS filter_list
                          ON filter_list.id =
                                filter_link.mailing_list_id
                        WHERE member.thread_id = thread.id
                          AND filter_list.archive_group =
                                \(scope.mailingList)
                    )
                  )
                ORDER BY
                    root.sent_at DESC NULLS LAST,
                    document.thread_id ASC
                LIMIT \(fetchLimit)
                OFFSET \(offset)
                """,
                logger: logger
            )
        }

        var matches: [ThreadSearchMatch] = []

        for try await row in rows {
            let cells = Array(row)

            matches.append(
                ThreadSearchMatch(
                    threadID: try cells[0]
                        .decode(Int64.self),
                    rootMessageID: try cells[1]
                        .decode(String.self),
                    score: try cells[2]
                        .decode(Double.self),
                    snippet: try cells[3]
                        .decode(String.self)
                )
            )
        }

        let hasNext = matches.count > scope.limit

        if hasNext {
            matches.removeLast()
        }

        let threads = try await PostgresReadRepository(
            client: client
        ).threads(
            threadIDs: matches.map(\.threadID),
            logger: logger
        )
        let threadsByRoot = Dictionary(
            uniqueKeysWithValues: threads.map {
                ($0.rootMessageID, $0)
            }
        )
        let values = matches.compactMap { match in
            threadsByRoot[match.rootMessageID].map {
                MailSearchResult(
                    thread: $0,
                    score: match.score,
                    snippet: match.snippet
                )
            }
        }

        return MailSearchPageResult(
            items: values,
            previousCursor: try offset > 0
                ? makeCursor(
                    offset: max(
                        0,
                        offset - scope.limit
                    ),
                    scope: scope
                )
                : nil,
            nextCursor: try hasNext
                ? makeCursor(
                    offset: offset + scope.limit,
                    scope: scope
                )
                : nil
        )
    }

    private func makeCursor(
        offset: Int,
        scope: MailSearchScope
    ) throws -> String {
        try PaginationCursorCodec.encode(
            MailSearchCursor(
                version: 1,
                offset: offset,
                scope: scope
            )
        )
    }
}

private struct ThreadSearchMatch {
    let threadID: Int64
    let rootMessageID: String
    let score: Double
    let snippet: String
}
