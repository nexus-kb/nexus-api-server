//
//  PublicInboxIngestJobs.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation
import NIOPosix
import PostgresNIO
import Queues
import Vapor

enum PublicInboxIngestJobError:
    Error,
    Sendable,
    Equatable
{
    case missingMailingList(Int64)
    case missingArchivePath(Int64)
    case missingEpoch(Int32)
    case invalidBatchSize(Int)
    case invalidMessageLimit(Int)
    case messageParseFailed(
        commitOID: String,
        blobOID: String,
        error: String
    )
}

struct PublicInboxEpochIngestTarget:
    Codable,
    Sendable,
    Equatable
{
    let queueJobID: String
    let epoch: Int32
    let repositoryPath: String
    let targetTipOID: String
}

struct ScanPublicInboxArchiveJob: AsyncJob {
    struct Payload:
        Codable,
        Sendable
    {
        let mailingListID: Int64
        let epoch: Int32?
        let batchSize: Int
        let runMessageLimitPerEpoch: Int? // Used to limit number of jobs during testing, nil in production.
    }
    
    func dequeue(
        _ context: QueueContext,
        _ payload: Payload
    ) async throws {
        guard
            PublicInboxIngestConfiguration
                .batchSizeRange
                .contains(payload.batchSize)
        else {
            throw PublicInboxIngestJobError
                .invalidBatchSize(
                    payload.batchSize
                )
        }

        if let limit =
                payload.runMessageLimitPerEpoch,
           limit < 1
        {
            throw PublicInboxIngestJobError
                .invalidMessageLimit(limit)
        }

        let archivePath = try await loadArchivePath(
            mailingListID: payload.mailingListID,
            context: context
        )

        let archive = PublicInboxArchive(
            rootURL: URL(
                fileURLWithPath: archivePath,
                isDirectory: true
            )
        )

        let epochs = try await context
            .application
            .threadPool
            .runIfActive {
                try archive.discoverEpochs()
            }

        let selectedEpochs: [PublicInboxEpoch]

        if let requestedEpoch = payload.epoch {
            guard let epoch = epochs.first(
                where: {
                    $0.number == requestedEpoch
                }
            ) else {
                throw PublicInboxIngestJobError
                    .missingEpoch(requestedEpoch)
            }

            selectedEpochs = [epoch]
        } else {
            selectedEpochs = epochs
        }

        var ingestTargets:
            [PublicInboxEpochIngestTarget] = []

        ingestTargets.reserveCapacity(
            selectedEpochs.count
        )

        for epoch in selectedEpochs {
            let targetTipOID =
                try await context
                .application
                .threadPool
                .runIfActive {
                    try PublicInboxEpochRepository(
                        epoch: epoch
                    ).tipOID()
                }

            ingestTargets.append(
                PublicInboxEpochIngestTarget(
                    queueJobID:
                        JobIdentifier().string,
                    epoch: epoch.number,
                    repositoryPath:
                        epoch.repositoryURL.path,
                    targetTipOID: targetTipOID
                )
            )
        }

        guard let firstTarget =
                ingestTargets.first
        else {
            return
        }

        try await IngestPublicInboxEpochJob
            .dispatch(
                .init(
                    mailingListID:
                        payload.mailingListID,
                    target: firstTarget,
                    remainingTargets: Array(
                        ingestTargets.dropFirst()
                    ),
                    batchSize: payload.batchSize,
                    remainingMessageLimit:
                        payload
                            .runMessageLimitPerEpoch
                ),
                context: context
            )
    }
    
    private func loadArchivePath(
        mailingListID: Int64,
        context: QueueContext
    ) async throws -> String {
        let rows = try await context
            .application
            .postgres
            .query(
                """
                SELECT archive_path
                FROM mailing_lists
                WHERE id = \(mailingListID)
                """,
                logger: context.logger
            )

        for try await row in rows {
            guard let path = try row.decode(
                String?.self
            ) else {
                throw PublicInboxIngestJobError
                    .missingArchivePath(
                        mailingListID
                    )
            }

            return path
        }

        throw PublicInboxIngestJobError
            .missingMailingList(
                mailingListID
            )
    }
}

struct IngestPublicInboxEpochJob: AsyncJob {
    struct Payload:
        Codable,
        Sendable
    {
        let mailingListID: Int64
        let target: PublicInboxEpochIngestTarget
        let remainingTargets:
            [PublicInboxEpochIngestTarget]
        let batchSize: Int
        let remainingMessageLimit: Int?

        func successor() -> Self? {
            guard let nextTarget =
                    remainingTargets.first
            else {
                return nil
            }

            return Self(
                mailingListID: mailingListID,
                target: nextTarget,
                remainingTargets: Array(
                    remainingTargets.dropFirst()
                ),
                batchSize: batchSize,
                remainingMessageLimit:
                    remainingMessageLimit
            )
        }
    }

    static func dispatch(
        _ payload: Payload,
        context: QueueContext
    ) async throws {
        try await context.queue.dispatch(
            Self.self,
            payload,
            maxRetryCount: 3,
            id: JobIdentifier(
                string: payload.target.queueJobID
            )
        )
    }

    static func prepare(
        _ entry: PublicInboxArchiveEntry,
        parser: IngestMessageParser =
            IngestMessageParser()
    ) throws -> PreparedPublicInboxArchiveEntry {
        switch entry {
        case .deletion(
            let commitOID,
            let blobOID
        ):
            return .deletion(
                commitOID: commitOID,
                blobOID: blobOID
            )

        case .message(let message):
            do {
                return .message(
                    PreparedPublicInboxMessage(
                        commitOID:
                            message.commitOID,
                        blobOID:
                            message.blobOID,
                        parsed: try parser.parse(
                            message.rawMessage
                        )
                    )
                )
            } catch IngestMessageParserError
                .missingMessageID
            {
                return .skipped(
                    commitOID: message.commitOID,
                    blobOID: message.blobOID
                )
            } catch {
                throw PublicInboxIngestJobError
                    .messageParseFailed(
                        commitOID:
                            message.commitOID,
                        blobOID:
                            message.blobOID,
                        error: String(
                            reflecting: error
                        )
                    )
            }
        }
    }

    func dequeue(
        _ context: QueueContext,
        _ payload: Payload
    ) async throws {
        guard
            PublicInboxIngestConfiguration
                .batchSizeRange
                .contains(payload.batchSize)
        else {
            throw PublicInboxIngestJobError
                .invalidBatchSize(
                    payload.batchSize
                )
        }

        if let limit = payload.remainingMessageLimit,
            limit < 1
        {
            throw
                PublicInboxIngestJobError
                .invalidMessageLimit(limit)
        }

        let store = PostgresIngestService(
            client: context.application.postgres
        )

        let initialCursor = try await store.archiveCursor(
            mailingListID: payload.mailingListID,
            epoch: payload.target.epoch,
            logger: context.logger
        )

        let epoch = PublicInboxEpoch(
            number: payload.target.epoch,
            repositoryURL: URL(
                fileURLWithPath:
                    payload.target.repositoryPath,
                isDirectory: true
            )
        )

        let repository =
            PublicInboxEpochRepository(
                epoch: epoch
            )

        let targetTipOID =
            payload.target.targetTipOID

        let manifest =
            try await context
            .application
            .threadPool
            .runIfActive {
                try repository
                    .makeRevisionManifest(
                        after: initialCursor,
                        through: targetTipOID
                    )
            }

        defer {
            manifest.remove()
        }

        let lease = PostgresQueueJobLease(
            client: context.application.postgres,
            jobID: payload.target.queueJobID,
            ownerID:
                context.application
                .postgresQueueLeaseOwner,
            logger: context.logger
        )

        try await lease.start()

        do {
            var expectedCursor = initialCursor
            var processedCount = 0

            while payload.remainingMessageLimit.map({
                processedCount < $0
            }) ?? true {
                try await lease.assertOwned()

                let remainingAllowance =
                    payload.remainingMessageLimit.map {
                        $0 - processedCount
                    }

                let nextBatchSize = min(
                    payload.batchSize,
                    remainingAllowance
                        ?? payload.batchSize
                )

                guard nextBatchSize > 0 else {
                    break
                }

                let commitOIDs =
                    try await context
                    .application
                    .threadPool
                    .runIfActive {
                        try manifest.nextBatch(
                            maximumCount:
                                nextBatchSize
                        )
                    }

                guard !commitOIDs.isEmpty else {
                    break
                }

                let entries =
                    try await context
                    .application
                    .threadPool
                    .runIfActive {
                        let parser =
                            IngestMessageParser()

                        return try repository
                            .loadEntries(
                                commitOIDs:
                                    commitOIDs
                            )
                            .map { entry in
                                try Self.prepare(
                                    entry,
                                    parser: parser
                                )
                            }
                    }

                for entry in entries {
                    guard case .skipped(
                        let commitOID,
                        let blobOID
                    ) = entry else {
                        continue
                    }

                    context.logger.warning(
                        "Skipped public-inbox message without a Message-ID",
                        metadata: [
                            "mailing-list-id":
                                "\(payload.mailingListID)",
                            "epoch":
                                "\(payload.target.epoch)",
                            "commit-oid":
                                "\(commitOID)",
                            "blob-oid":
                                "\(blobOID)",
                        ]
                    )
                }

                try await lease.assertOwned()

                _ = try await store.ingestBatch(
                    entries,
                    mailingListID:
                        payload.mailingListID,
                    epoch: payload.target.epoch,
                    expectedPreviousCommitOID:
                        expectedCursor,
                    logger: context.logger
                )

                expectedCursor =
                    entries.last?.commitOID
                    ?? expectedCursor

                let counts = entries.reduce(
                    into: (
                        messages: 0,
                        deletions: 0,
                        skipped: 0
                    )
                ) { counts, entry in
                    switch entry {
                    case .message:
                        counts.messages += 1
                    case .deletion:
                        counts.deletions += 1
                    case .skipped:
                        counts.skipped += 1
                    }
                }

                processedCount += counts.messages

                context.logger.info(
                    "Ingested public-inbox database batch",
                    metadata: [
                        "mailing-list-id":
                            "\(payload.mailingListID)",
                        "epoch":
                            "\(payload.target.epoch)",
                        "message-count":
                            "\(counts.messages)",
                        "deletion-count":
                            "\(counts.deletions)",
                        "skipped-count":
                            "\(counts.skipped)",
                        "scanned-commit-count":
                            "\(entries.count)",
                        "total-message-count":
                            "\(processedCount)",
                        "cursor":
                            "\(expectedCursor ?? "")",
                        "target-tip":
                            "\(targetTipOID)",
                    ]
                )
            }

            if let successor =
                    payload.successor()
            {
                try await Self.dispatch(
                    successor,
                    context: context
                )
            }

            await lease.stop()
        } catch {
            await lease.stop()
            throw error
        }
    }
}
