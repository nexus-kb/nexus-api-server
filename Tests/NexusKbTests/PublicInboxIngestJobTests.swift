@testable import NexusKb
import Foundation
import Testing

@Suite("Public-inbox ingest job tests")
struct PublicInboxIngestJobTests {
    @Test("Epoch payload advances one target at a time")
    func advancesOneEpochAtATime() {
        let targets = (0..<3).map {
            PublicInboxEpochIngestTarget(
                queueJobID: "job-\($0)",
                epoch: Int32($0),
                repositoryPath: "/archive/git/\($0).git",
                targetTipOID: "tip-\($0)"
            )
        }

        let first = IngestPublicInboxEpochJob.Payload(
            mailingListID: 2,
            target: targets[0],
            remainingTargets: Array(
                targets.dropFirst()
            ),
            batchSize: 10_000,
            remainingMessageLimit: nil
        )

        let second = first.successor()
        let third = second?.successor()

        #expect(first.target == targets[0])
        #expect(first.remainingTargets == [
            targets[1],
            targets[2],
        ])
        #expect(second?.target == targets[1])
        #expect(second?.remainingTargets == [targets[2]])
        #expect(third?.target == targets[2])
        #expect(third?.remainingTargets.isEmpty == true)
        #expect(third?.successor() == nil)
    }

    @Test("Messages without an identifier are skipped")
    func skipsMessageWithoutIdentifier() throws {
        let commitOID = String(
            repeating: "a",
            count: 40
        )
        let blobOID = String(
            repeating: "b",
            count: 40
        )
        let rawMessage = Data(
            """
            From: person@example.com
            Message-ID:
            Subject: Missing identifier

            Body
            """.utf8
        )

        let prepared = try IngestPublicInboxEpochJob
            .prepare(
                .message(
                    PublicInboxCommit(
                        commitOID: commitOID,
                        blobOID: blobOID,
                        rawMessage: rawMessage
                    )
                )
            )

        guard case .skipped(
            let actualCommitOID,
            let actualBlobOID
        ) = prepared else {
            Issue.record(
                "Expected missing Message-ID to be skipped"
            )
            return
        }

        #expect(actualCommitOID == commitOID)
        #expect(actualBlobOID == blobOID)
    }

    @Test("Other parse failures remain fatal")
    func rejectsUnparseableMessage() {
        let commitOID = String(
            repeating: "c",
            count: 40
        )
        let blobOID = String(
            repeating: "d",
            count: 40
        )

        #expect(
            throws: PublicInboxIngestJobError
                .messageParseFailed(
                    commitOID: commitOID,
                    blobOID: blobOID,
                    error:
                        "NexusKb.IngestMessageParserError.unparseableMessage"
                )
        ) {
            try IngestPublicInboxEpochJob.prepare(
                .message(
                    PublicInboxCommit(
                        commitOID: commitOID,
                        blobOID: blobOID,
                        rawMessage: Data()
                    )
                )
            )
        }
    }
}
