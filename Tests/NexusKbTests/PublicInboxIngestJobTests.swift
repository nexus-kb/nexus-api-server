@testable import NexusKb
import Foundation
import Testing

@Suite("Maintenance workflow unit tests")
struct MaintenanceWorkflowUnitTests {
    @Test("Messages without an identifier are skipped")
    func skipsMessageWithoutIdentifier() throws {
        let commitOID = String(repeating: "a", count: 40)
        let blobOID = String(repeating: "b", count: 40)
        let prepared = try PublicInboxEntryPreparation.prepare(
            .message(
                PublicInboxCommit(
                    commitOID: commitOID,
                    blobOID: blobOID,
                    rawMessage: Data(
                        """
                        From: person@example.com
                        Message-ID:
                        Subject: Missing identifier

                        Body
                        """.utf8
                    )
                )
            )
        )

        guard case .skipped(let actualCommitOID, let actualBlobOID) = prepared else {
            Issue.record("Expected missing Message-ID to be skipped")
            return
        }
        #expect(actualCommitOID == commitOID)
        #expect(actualBlobOID == blobOID)
    }

    @Test("Other parse failures remain fatal")
    func rejectsUnparseableMessage() {
        let commitOID = String(repeating: "c", count: 40)
        let blobOID = String(repeating: "d", count: 40)

        #expect(
            throws: PublicInboxEntryPreparationError.messageParseFailed(
                commitOID: commitOID,
                blobOID: blobOID,
                error: "NexusKb.IngestMessageParserError.unparseableMessage"
            )
        ) {
            try PublicInboxEntryPreparation.prepare(
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
