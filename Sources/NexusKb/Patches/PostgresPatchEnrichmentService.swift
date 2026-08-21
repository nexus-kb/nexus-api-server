import PostgresNIO
import Vapor

enum PostgresPatchEnrichmentError:
    Error,
    Sendable,
    Equatable
{
    case missingPatch(Int64)
    case missingInsertedRun
    case missingInsertedFile(Int)
    case missingInsertedHunk(
        fileIndex: Int,
        hunkIndex: Int
    )
    case integerOverflow(Int)
    case extractorVersionMismatch(
        expected: String,
        actual: String
    )
    case invalidFileIndex(Int)
    case invalidHunkIndex(
        fileIndex: Int,
        hunkIndex: Int
    )
    case filePathMismatch(
        fileIndex: Int,
        expected: String?,
        actual: String
    )
    case invalidLineCoordinate(
        fileIndex: Int,
        hunkIndex: Int,
        lineIndex: Int?
    )
}

struct PostgresPatchEnrichmentService: Sendable {
    let client: PostgresClient

    func rebuild(
        patchID: Int64,
        logger: Logger
    ) async throws -> PatchEnrichmentPersistenceSummary {
        try await client.withTransaction(
            logger: logger
        ) { connection in
            let diff = try await canonicalDiff(
                patchID: patchID,
                connection: connection,
                logger: logger
            )
            let document = try PatchDocumentParser()
                .parse(diff)
            let observations = PatchSymbolAttributor()
                .observations(in: document)

            return try await replace(
                patchID: patchID,
                document: document,
                observations: observations,
                extractorVersion:
                    PatchSymbolAttributor
                    .extractorVersion,
                connection: connection,
                logger: logger
            )
        }
    }

    func delete(
        patchID: Int64,
        extractorVersion: String,
        logger: Logger
    ) async throws -> Bool {
        try await client.withTransaction(
            logger: logger
        ) { connection in
            guard try await lockPatch(
                patchID: patchID,
                connection: connection,
                logger: logger
            ) else {
                return false
            }

            let rows = try await connection.query(
                """
                DELETE FROM enrichment_runs
                WHERE patch_id = \(patchID)
                  AND extractor_version =
                        \(extractorVersion)
                RETURNING id
                """,
                logger: logger
            )

            for try await _ in rows {
                return true
            }

            return false
        }
    }

    private func lockPatch(
        patchID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Bool {
        let rows = try await connection.query(
            """
            SELECT id
            FROM patches
            WHERE id = \(patchID)
            FOR UPDATE
            """,
            logger: logger
        )

        for try await _ in rows {
            return true
        }

        return false
    }

    private func canonicalDiff(
        patchID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> String {
        let rows = try await connection.query(
            """
            SELECT diff
            FROM patches
            WHERE id = \(patchID)
            FOR UPDATE
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(String.self)
        }

        throw
            PostgresPatchEnrichmentError
            .missingPatch(patchID)
    }

    private func replace(
        patchID: Int64,
        document: PatchDocument,
        observations: [PatchSymbolObservation],
        extractorVersion: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> PatchEnrichmentPersistenceSummary {
        try validate(
            observations,
            in: document,
            extractorVersion: extractorVersion
        )

        try await execute(
            """
            DELETE FROM enrichment_runs
            WHERE patch_id = \(patchID)
              AND extractor_version =
                    \(extractorVersion)
            """,
            connection: connection,
            logger: logger
        )

        let runID = try await insertRun(
            patchID: patchID,
            extractorVersion: extractorVersion,
            connection: connection,
            logger: logger
        )
        var fileIDs: [Int64] = []
        var hunkIDs: [[Int64]] = []

        for (fileIndex, file)
            in document.files.enumerated()
        {
            let fileID = try await insertFile(
                file,
                fileIndex: fileIndex,
                patchID: patchID,
                runID: runID,
                extractorVersion: extractorVersion,
                connection: connection,
                logger: logger
            )
            var fileHunkIDs: [Int64] = []

            for (hunkIndex, hunk)
                in file.hunks.enumerated()
            {
                fileHunkIDs.append(
                    try await insertHunk(
                        hunk,
                        fileIndex: fileIndex,
                        hunkIndex: hunkIndex,
                        fileID: fileID,
                        patchID: patchID,
                        runID: runID,
                        extractorVersion:
                            extractorVersion,
                        connection: connection,
                        logger: logger
                    )
                )
            }

            fileIDs.append(fileID)
            hunkIDs.append(fileHunkIDs)
        }

        for observation in observations {
            let fileID = fileIDs[
                observation.fileIndex
            ]
            let hunkID = hunkIDs[
                observation.fileIndex
            ][observation.hunkIndex]

            try await insertObservation(
                observation,
                fileID: fileID,
                hunkID: hunkID,
                patchID: patchID,
                runID: runID,
                extractorVersion: extractorVersion,
                connection: connection,
                logger: logger
            )
        }

        return PatchEnrichmentPersistenceSummary(
            runID: runID,
            patchID: patchID,
            extractorVersion: extractorVersion,
            fileCount: document.files.count,
            hunkCount: document.files
                .reduce(0) {
                    $0 + $1.hunks.count
                },
            observationCount: observations.count
        )
    }

    private func insertRun(
        patchID: Int64,
        extractorVersion: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let rows = try await connection.query(
            """
            INSERT INTO enrichment_runs (
                patch_id,
                extractor_version
            )
            VALUES (
                \(patchID),
                \(extractorVersion)
            )
            RETURNING id
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        throw
            PostgresPatchEnrichmentError
            .missingInsertedRun
    }

    private func insertFile(
        _ file: PatchChangedFile,
        fileIndex: Int,
        patchID: Int64,
        runID: Int64,
        extractorVersion: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let databaseFileIndex = try databaseInteger(
            fileIndex
        )
        let rows = try await connection.query(
            """
            INSERT INTO patch_diff_files (
                patch_id,
                enrichment_run_id,
                extractor_version,
                file_index,
                old_path,
                new_path,
                operation,
                diff_header,
                header_lines,
                trailing_lines
            )
            VALUES (
                \(patchID),
                \(runID),
                \(extractorVersion),
                \(databaseFileIndex),
                \(file.oldPath),
                \(file.newPath),
                \(file.operation.rawValue),
                \(file.diffHeader),
                \(file.headerLines)::text[],
                \(file.trailingLines)::text[]
            )
            RETURNING id
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        throw
            PostgresPatchEnrichmentError
            .missingInsertedFile(fileIndex)
    }

    private func insertHunk(
        _ hunk: PatchHunk,
        fileIndex: Int,
        hunkIndex: Int,
        fileID: Int64,
        patchID: Int64,
        runID: Int64,
        extractorVersion: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let databaseHunkIndex = try databaseInteger(
            hunkIndex
        )
        let oldStart = try databaseInteger(
            hunk.oldRange.start
        )
        let oldCount = try databaseInteger(
            hunk.oldRange.count
        )
        let newStart = try databaseInteger(
            hunk.newRange.start
        )
        let newCount = try databaseInteger(
            hunk.newRange.count
        )
        let rows = try await connection.query(
            """
            INSERT INTO patch_diff_hunks (
                patch_id,
                enrichment_run_id,
                extractor_version,
                file_id,
                hunk_index,
                old_start,
                old_count,
                new_start,
                new_count,
                section_header,
                raw_header
            )
            VALUES (
                \(patchID),
                \(runID),
                \(extractorVersion),
                \(fileID),
                \(databaseHunkIndex),
                \(oldStart),
                \(oldCount),
                \(newStart),
                \(newCount),
                \(hunk.sectionHeader),
                \(hunk.rawHeader)
            )
            RETURNING id
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        throw
            PostgresPatchEnrichmentError
            .missingInsertedHunk(
                fileIndex: fileIndex,
                hunkIndex: hunkIndex
            )
    }

    private func insertObservation(
        _ observation: PatchSymbolObservation,
        fileID: Int64,
        hunkID: Int64,
        patchID: Int64,
        runID: Int64,
        extractorVersion: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let lineIndex: Int32?

        if let value = observation.lineIndex {
            lineIndex = try databaseInteger(value)
        } else {
            lineIndex = nil
        }

        try await execute(
            """
            INSERT INTO patch_symbol_observations (
                patch_id,
                enrichment_run_id,
                extractor_version,
                file_id,
                hunk_id,
                symbol_name,
                symbol_kind,
                relationship,
                line_index,
                line_kind,
                evidence_method,
                confidence
            )
            VALUES (
                \(patchID),
                \(runID),
                \(extractorVersion),
                \(fileID),
                \(hunkID),
                \(observation.symbol.name),
                \(observation.symbol.kind.rawValue),
                \(observation.relationship.rawValue),
                \(lineIndex),
                \(observation.lineKind?.rawValue),
                \(observation.evidenceMethod.rawValue),
                \(observation.confidence)
            )
            """,
            connection: connection,
            logger: logger
        )
    }

    private func validate(
        _ observations: [PatchSymbolObservation],
        in document: PatchDocument,
        extractorVersion: String
    ) throws {
        for observation in observations {
            guard observation.extractorVersion
                == extractorVersion
            else {
                throw
                    PostgresPatchEnrichmentError
                    .extractorVersionMismatch(
                        expected: extractorVersion,
                        actual:
                            observation.extractorVersion
                    )
            }

            guard document.files.indices.contains(
                observation.fileIndex
            ) else {
                throw
                    PostgresPatchEnrichmentError
                    .invalidFileIndex(
                        observation.fileIndex
                    )
            }

            let file = document.files[
                observation.fileIndex
            ]

            guard file.path == observation.filePath else {
                throw
                    PostgresPatchEnrichmentError
                    .filePathMismatch(
                        fileIndex:
                            observation.fileIndex,
                        expected: file.path,
                        actual: observation.filePath
                    )
            }

            guard file.hunks.indices.contains(
                observation.hunkIndex
            ) else {
                throw
                    PostgresPatchEnrichmentError
                    .invalidHunkIndex(
                        fileIndex:
                            observation.fileIndex,
                        hunkIndex:
                            observation.hunkIndex
                    )
            }

            let hunk = file.hunks[
                observation.hunkIndex
            ]

            switch (
                observation.lineIndex,
                observation.lineKind
            ) {
            case (nil, nil):
                break
            case let (lineIndex?, lineKind?):
                guard hunk.lines.indices.contains(
                    lineIndex
                ), hunk.lines[lineIndex].kind == lineKind
                else {
                    throw
                        PostgresPatchEnrichmentError
                        .invalidLineCoordinate(
                            fileIndex:
                                observation.fileIndex,
                            hunkIndex:
                                observation.hunkIndex,
                            lineIndex: lineIndex
                        )
                }
            default:
                throw
                    PostgresPatchEnrichmentError
                    .invalidLineCoordinate(
                        fileIndex:
                            observation.fileIndex,
                        hunkIndex:
                            observation.hunkIndex,
                        lineIndex:
                            observation.lineIndex
                    )
            }
        }
    }

    private func databaseInteger(
        _ value: Int
    ) throws -> Int32 {
        guard let result = Int32(exactly: value) else {
            throw
                PostgresPatchEnrichmentError
                .integerOverflow(value)
        }

        return result
    }

    private func execute(
        _ query: PostgresQuery,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let rows = try await connection.query(
            query,
            logger: logger
        )

        for try await _ in rows {}
    }
}
