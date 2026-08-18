@testable import NexusKb
import Foundation
import Testing

@Suite("Public-inbox revision manifest tests")
struct PublicInboxRevisionManifestTests {
    @Test("Manifest preserves oldest-to-newest order")
    func preservesOrder() throws {
        let repository = try TemporaryGitRepository()
        let first = try repository.commit("first")
        let second = try repository.commit("second")
        let third = try repository.commit("third")

        let manifest = try repository.subject
            .makeRevisionManifest(
                after: nil,
                through: third
            )
        defer { manifest.remove() }

        #expect(
            try manifest.nextBatch(maximumCount: 10)
                == [first, second, third]
        )
        #expect(
            try manifest.nextBatch(maximumCount: 10)
                .isEmpty
        )
    }

    @Test("Manifest excludes the durable cursor")
    func excludesCursor() throws {
        let repository = try TemporaryGitRepository()
        let first = try repository.commit("first")
        let second = try repository.commit("second")
        let third = try repository.commit("third")

        let manifest = try repository.subject
            .makeRevisionManifest(
                after: first,
                through: third
            )
        defer { manifest.remove() }

        #expect(
            try manifest.nextBatch(maximumCount: 10)
                == [second, third]
        )
    }

    @Test("Fixed target excludes commits added later")
    func fixedTargetSnapshot() throws {
        let repository = try TemporaryGitRepository()
        let first = try repository.commit("first")
        let target = try repository.commit("target")
        _ = try repository.commit("later")

        let manifest = try repository.subject
            .makeRevisionManifest(
                after: nil,
                through: target
            )
        defer { manifest.remove() }

        #expect(
            try manifest.nextBatch(maximumCount: 10)
                == [first, target]
        )
    }

    @Test("Completed and older snapshots are empty")
    func completedSnapshots() throws {
        let repository = try TemporaryGitRepository()
        let first = try repository.commit("first")
        let second = try repository.commit("second")

        let completed = try repository.subject
            .makeRevisionManifest(
                after: second,
                through: second
            )
        defer { completed.remove() }

        #expect(
            try completed.nextBatch(maximumCount: 1)
                .isEmpty
        )

        let passed = try repository.subject
            .makeRevisionManifest(
                after: second,
                through: first
            )
        defer { passed.remove() }

        #expect(
            try passed.nextBatch(maximumCount: 1)
                .isEmpty
        )
    }

    @Test("Diverged cursor and target are rejected")
    func rejectsDivergedHistory() throws {
        let repository = try TemporaryGitRepository()
        let root = try repository.commit("root")

        try repository.run([
            "checkout",
            "-b",
            "side",
            root,
        ])
        let side = try repository.commit("side")

        try repository.run([
            "checkout",
            "master",
        ])
        let master = try repository.commit("master")

        #expect(
            throws:
                PublicInboxArchiveError
                .cursorAndTipHaveDiverged(
                    cursor: side,
                    tip: master
                )
        ) {
            try repository.subject
                .makeRevisionManifest(
                    after: side,
                    through: master
                )
        }
    }

    @Test("Large manifest is consumed in bounded batches")
    func boundedBatches() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nexus-kb-manifest-test-\(UUID().uuidString)"
            )

        let values = (0..<25_001).map {
            String(format: "%040x", $0)
        }

        try Data(
            (values.joined(separator: "\n") + "\n")
                .utf8
        ).write(to: url)

        let manifest = try PublicInboxRevisionManifest(
            url: url
        )
        defer { manifest.remove() }

        let first = try manifest.nextBatch(
            maximumCount: 10_000
        )
        let second = try manifest.nextBatch(
            maximumCount: 10_000
        )
        let third = try manifest.nextBatch(
            maximumCount: 10_000
        )

        #expect(first.count == 10_000)
        #expect(second.count == 10_000)
        #expect(third.count == 5_001)
        #expect(first.first == values.first)
        #expect(third.last == values.last)
        #expect(Set(first + second + third).count == 25_001)
        #expect(
            try manifest.nextBatch(maximumCount: 1)
                .isEmpty
        )
    }

    @Test("Configured archive batch size is ten thousand")
    func configuredBatchSize() {
        #expect(
            PublicInboxIngestConfiguration
                .defaultBatchSize == 10_000
        )
        #expect(
            PublicInboxIngestConfiguration
                .batchSizeRange == 1...10_000
        )
    }
}

private final class TemporaryGitRepository {
    let url: URL

    var subject: PublicInboxEpochRepository {
        PublicInboxEpochRepository(
            epoch: PublicInboxEpoch(
                number: 0,
                repositoryURL: url
            )
        )
    }

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nexus-kb-git-test-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        try run([
            "init",
            "-b",
            "master",
        ])
        try run([
            "config",
            "user.name",
            "Nexus KB Test",
        ])
        try run([
            "config",
            "user.email",
            "nexus-kb-test@example.com",
        ])
    }

    deinit {
        try? FileManager.default.removeItem(
            at: url
        )
    }

    func commit(_ value: String) throws -> String {
        try Data(value.utf8).write(
            to: url.appendingPathComponent("m")
        )

        try run([
            "add",
            "m",
        ])
        try run([
            "commit",
            "-m",
            value,
        ])

        return try text([
            "rev-parse",
            "HEAD",
        ])
    }

    func run(_ arguments: [String]) throws {
        _ = try execute(arguments)
    }

    private func text(_ arguments: [String]) throws -> String {
        String(
            decoding: try execute(arguments),
            as: UTF8.self
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func execute(
        _ arguments: [String]
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/git"
        )
        process.arguments = [
            "-C",
            url.path,
        ] + arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()

        let outputData = output
            .fileHandleForReading
            .readDataToEndOfFile()
        let errorData = error
            .fileHandleForReading
            .readDataToEndOfFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TemporaryGitRepositoryError.gitFailed(
                String(
                    decoding: errorData,
                    as: UTF8.self
                )
            )
        }

        return outputData
    }
}

private enum TemporaryGitRepositoryError: Error {
    case gitFailed(String)
}
