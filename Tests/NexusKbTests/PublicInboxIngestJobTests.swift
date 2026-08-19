@testable import NexusKb
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
}
