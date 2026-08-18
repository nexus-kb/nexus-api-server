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

            let jobID = JobIdentifier()

            try await context.queue.dispatch(
                IngestPublicInboxEpochJob.self,
                .init(
                    queueJobID: jobID.string,
                    mailingListID:
                        payload.mailingListID,
                    epoch: epoch.number,
                    repositoryPath:
                        epoch.repositoryURL.path,
                    targetTipOID: targetTipOID,
                    batchSize: payload.batchSize,
                    remainingMessageLimit:
                        payload
                            .runMessageLimitPerEpoch
                ),
                maxRetryCount: 3,
                id: jobID
            )
        }
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
        let queueJobID: String
        let mailingListID: Int64
        let epoch: Int32
        let repositoryPath: String
        let targetTipOID: String?
        let batchSize: Int
        let remainingMessageLimit: Int?
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
            epoch: payload.epoch,
            logger: context.logger
        )

        let epoch = PublicInboxEpoch(
            number: payload.epoch,
            repositoryURL: URL(
                fileURLWithPath:
                    payload.repositoryPath,
                isDirectory: true
            )
        )

        let repository =
            PublicInboxEpochRepository(
                epoch: epoch
            )

        let targetTipOID =
            try await context
            .application
            .threadPool
            .runIfActive {
                try payload.targetTipOID
                    ?? repository.tipOID()
            }

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
            jobID: payload.queueJobID,
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

                let messages =
                    try await context
                    .application
                    .threadPool
                    .runIfActive {
                        let parser =
                            IngestMessageParser()

                        return
                            try repository
                            .loadMessages(
                                commitOIDs:
                                    commitOIDs
                            )
                            .map {
                                PreparedPublicInboxMessage(
                                    commitOID:
                                        $0.commitOID,
                                    blobOID:
                                        $0.blobOID,
                                    parsed:
                                        try parser.parse(
                                            $0.rawMessage
                                        )
                                )
                            }
                    }

                try await lease.assertOwned()

                _ = try await store.ingestBatch(
                    messages,
                    mailingListID:
                        payload.mailingListID,
                    epoch: payload.epoch,
                    expectedPreviousCommitOID:
                        expectedCursor,
                    logger: context.logger
                )

                expectedCursor =
                    messages.last?.commitOID
                    ?? expectedCursor

                processedCount += messages.count

                context.logger.info(
                    "Ingested public-inbox database batch",
                    metadata: [
                        "mailing-list-id":
                            "\(payload.mailingListID)",
                        "epoch":
                            "\(payload.epoch)",
                        "message-count":
                            "\(messages.count)",
                        "total-message-count":
                            "\(processedCount)",
                        "cursor":
                            "\(expectedCursor ?? "")",
                        "target-tip":
                            "\(targetTipOID)",
                    ]
                )
            }

            await lease.stop()
        } catch {
            await lease.stop()
            throw error
        }
    }
}
