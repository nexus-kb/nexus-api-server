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
        guard (1...500).contains(
            payload.batchSize
        ) else {
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
            try await context.queue.dispatch(
                IngestPublicInboxEpochJob.self,
                .init(
                    mailingListID:
                        payload.mailingListID,
                    epoch: epoch.number,
                    repositoryPath:
                        epoch.repositoryURL.path,
                    targetTipOID: nil,
                    batchSize: payload.batchSize,
                    remainingMessageLimit:
                        payload
                            .runMessageLimitPerEpoch
                ),
                maxRetryCount: 3
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
        let mailingListID: Int64
        let epoch: Int32
        let repositoryPath: String
        let targetTipOID: String?
        let batchSize: Int
        let remainingMessageLimit: Int?
    }

    private struct PreparedMessage:
        Sendable
    {
        let commit: PublicInboxCommit
        let parsed: ParsedIngestMessage
    }

    private struct PreparedBatch:
        Sendable
    {
        let targetTipOID: String
        let availableCount: Int
        let messages: [PreparedMessage]
    }

    func dequeue(
        _ context: QueueContext,
        _ payload: Payload
    ) async throws {
        guard (1...500).contains(
            payload.batchSize
        ) else {
            throw PublicInboxIngestJobError
                .invalidBatchSize(
                    payload.batchSize
                )
        }

        let store = PostgresIngestService(
            client: context.application.postgres
        )

        let cursor = try await store.archiveCursor(
            mailingListID: payload.mailingListID,
            epoch: payload.epoch,
            logger: context.logger
        )

        let allowedCount = min(
            payload.batchSize,
            payload.remainingMessageLimit
                ?? payload.batchSize
        )

        guard allowedCount > 0 else {
            return
        }

        let batch = try await context
            .application
            .threadPool
            .runIfActive {
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
                    try payload.targetTipOID
                    ?? repository.tipOID()

                let available = try repository
                    .commitOIDs(
                        after: cursor,
                        through: targetTipOID
                    )

                let selected = Array(
                    available.prefix(allowedCount)
                )

                let parser =
                    IngestMessageParser()

                let messages = try repository
                    .loadMessages(
                        commitOIDs: selected
                    )
                    .map {
                        PreparedMessage(
                            commit: $0,
                            parsed: try parser.parse(
                                $0.rawMessage
                            )
                        )
                    }

                return PreparedBatch(
                    targetTipOID: targetTipOID,
                    availableCount:
                        available.count,
                    messages: messages
                )
            }

        guard !batch.messages.isEmpty else {
            context.logger.info(
                "Public-inbox epoch is current",
                metadata: [
                    "mailing-list-id":
                        "\(payload.mailingListID)",
                    "epoch": "\(payload.epoch)",
                ]
            )
            return
        }

        var expectedCursor = cursor

        for message in batch.messages {
            _ = try await store.ingest(
                commit: message.commit,
                parsed: message.parsed,
                mailingListID:
                    payload.mailingListID,
                epoch: payload.epoch,
                expectedPreviousCommitOID:
                    expectedCursor,
                logger: context.logger
            )

            expectedCursor =
                message.commit.commitOID
        }

        let remainingLimit =
            payload.remainingMessageLimit.map {
                $0 - batch.messages.count
            }

        let hasMoreInSnapshot =
            batch.availableCount
            > batch.messages.count

        let mayContinue =
            remainingLimit == nil
            || remainingLimit! > 0

        if hasMoreInSnapshot && mayContinue {
            try await context.queue.dispatch(
                Self.self,
                .init(
                    mailingListID:
                        payload.mailingListID,
                    epoch: payload.epoch,
                    repositoryPath:
                        payload.repositoryPath,
                    targetTipOID:
                        batch.targetTipOID,
                    batchSize:
                        payload.batchSize,
                    remainingMessageLimit:
                        remainingLimit
                ),
                maxRetryCount: 3
            )
        }

        context.logger.info(
            "Ingested public-inbox batch",
            metadata: [
                "mailing-list-id":
                    "\(payload.mailingListID)",
                "epoch": "\(payload.epoch)",
                "message-count":
                    "\(batch.messages.count)",
                "cursor":
                    "\(expectedCursor ?? "")",
            ]
        )
    }
}
