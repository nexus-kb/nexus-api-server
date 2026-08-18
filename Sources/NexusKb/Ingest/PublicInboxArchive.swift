//
//  PublicInboxArchive.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation

struct PublicInboxEpoch: Sendable, Equatable {
    let number: Int32
    let repositoryURL: URL
}

struct PublicInboxCommit: Sendable, Equatable {
    let commitOID: String
    let blobOID: String
    let rawMessage: Data
}

final class PublicInboxRevisionManifest:
    @unchecked Sendable
{
    private let url: URL
    private let fileHandle: FileHandle
    private var buffer = Data()
    private var reachedEnd = false
    private var wasRemoved = false

    init(url: URL) throws {
        self.url = url
        self.fileHandle = try FileHandle(
            forReadingFrom: url
        )
    }

    func nextBatch(
        maximumCount: Int
    ) throws -> [String] {
        guard maximumCount > 0 else {
            return []
        }

        var result: [String] = []
        result.reserveCapacity(maximumCount)

        while result.count < maximumCount,
            let oid = try nextOID()
        {
            result.append(oid)
        }

        return result
    }

    func remove() {
        guard !wasRemoved else {
            return
        }

        wasRemoved = true

        try? fileHandle.close()
        try? FileManager.default.removeItem(
            at: url
        )
    }

    deinit {
        remove()
    }

    private func nextOID() throws -> String? {
        while true {
            if let newline =
                buffer.firstIndex(of: 10)
            {
                let lineData =
                    buffer[..<newline]

                buffer.removeSubrange(
                    buffer.startIndex...newline
                )

                guard !lineData.isEmpty else {
                    continue
                }

                guard
                    let oid = String(
                        data: lineData,
                        encoding: .utf8
                    )
                else {
                    throw
                        PublicInboxArchiveError
                        .invalidRevisionManifest(
                            "OID was not UTF-8"
                        )
                }

                return oid
            }

            if reachedEnd {
                guard !buffer.isEmpty else {
                    return nil
                }

                let lineData = buffer
                buffer.removeAll(
                    keepingCapacity: false
                )

                guard
                    let oid = String(
                        data: lineData,
                        encoding: .utf8
                    ),
                    !oid.isEmpty
                else {
                    throw
                        PublicInboxArchiveError
                        .invalidRevisionManifest(
                            "invalid final OID"
                        )
                }

                return oid
            }

            let chunk = try fileHandle.read(
                upToCount: 64 * 1_024
            )

            guard let chunk,
                !chunk.isEmpty
            else {
                reachedEnd = true
                continue
            }

            buffer.append(chunk)
        }
    }
}

enum PublicInboxArchiveError:
    Error,
    Sendable,
    Equatable
{
    case missingGitDirectory(String)
    case noEpochs(String)
    case gitFailed(
        arguments: [String],
        status: Int32,
        message: String
    )
    case invalidGitOutput(String)
    case cursorIsNotAncestor(
        cursor: String,
        tip: String
    )
    case missingMessageBlob(String)
    case batchTooLarge(Int)
    case cursorAndTipHaveDiverged(
        cursor: String,
        tip: String
    )
    case invalidRevisionManifest(String)
    case unableToCreateTemporaryFile(String)
}

struct PublicInboxArchive: Sendable {
    let rootURL: URL

    func discoverEpochs() throws
        -> [PublicInboxEpoch]
    {
        let gitDirectory = rootURL.appendingPathComponent(
            "git",
            isDirectory: true
        )

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: gitDirectory.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue
        else {
            throw PublicInboxArchiveError
                .missingGitDirectory(
                    gitDirectory.path
                )
        }

        let children =
            try FileManager.default.contentsOfDirectory(
                at: gitDirectory,
                includingPropertiesForKeys: [
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            )

        let epochs = try children.compactMap {
            child -> PublicInboxEpoch? in

            guard child.pathExtension == "git",
                  let number = Int32(
                      child
                          .deletingPathExtension()
                          .lastPathComponent
                  ),
                  number >= 0,
                  try child.resourceValues(
                      forKeys: [.isDirectoryKey]
                  ).isDirectory == true
            else {
                return nil
            }

            return PublicInboxEpoch(
                number: number,
                repositoryURL: child
            )
        }.sorted {
            $0.number < $1.number
        }

        guard !epochs.isEmpty else {
            throw PublicInboxArchiveError.noEpochs(
                rootURL.path
            )
        }

        return epochs
    }
}

struct PublicInboxEpochRepository: Sendable {
    let epoch: PublicInboxEpoch

    private let git = GitProcess()

    func tipOID() throws -> String {
        try git.text(
            arguments: [
                "-C",
                epoch.repositoryURL.path,
                "rev-parse",
                "--verify",
                "refs/heads/master^{commit}",
            ]
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    func makeRevisionManifest(
        after cursor: String?,
        through tip: String
    ) throws -> PublicInboxRevisionManifest {
        if let cursor {
            if cursor == tip {
                return try emptyRevisionManifest()
            }

            if try isAncestor(
                tip,
                of: cursor
            ) {
                return try emptyRevisionManifest()
            }

            guard
                try isAncestor(
                    cursor,
                    of: tip
                )
            else {
                throw PublicInboxArchiveError
                    .cursorAndTipHaveDiverged(
                        cursor: cursor,
                        tip: tip
                    )
            }
        }

        let revision = cursor.map {
            "\($0)..\(tip)"
        } ?? tip

        let manifestURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nexus-kb-\(UUID().uuidString).oids"
            )

        do {
            try git.run(
                arguments: [
                    "-C",
                    epoch.repositoryURL.path,
                    "rev-list",
                    "--reverse",
                    "--first-parent",
                    revision,
                ],
                standardOutputURL: manifestURL
            )

            return try PublicInboxRevisionManifest(
                url: manifestURL
            )
        } catch {
            try? FileManager.default.removeItem(
                at: manifestURL
            )
            throw error
        }
    }

    private func isAncestor(
        _ ancestor: String,
        of descendant: String
    ) throws -> Bool {
        let result = try git.run(
            arguments: [
                "-C",
                epoch.repositoryURL.path,
                "merge-base",
                "--is-ancestor",
                ancestor,
                descendant,
            ],
            acceptedStatuses: [0, 1]
        )

        return result.status == 0
    }

    private func emptyRevisionManifest()
        throws -> PublicInboxRevisionManifest
    {
        let manifestURL =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nexus-kb-\(UUID().uuidString).oids"
            )

        guard
            FileManager.default.createFile(
                atPath: manifestURL.path,
                contents: Data()
            )
        else {
            throw
                PublicInboxArchiveError
                .unableToCreateTemporaryFile(
                    manifestURL.path
                )
        }

        return try PublicInboxRevisionManifest(
            url: manifestURL
        )
    }

    func loadMessages(
        commitOIDs: [String]
    ) throws -> [PublicInboxCommit] {
        guard !commitOIDs.isEmpty else {
            return []
        }

        guard
            PublicInboxIngestConfiguration
                .batchSizeRange
                .contains(commitOIDs.count)
        else {
            throw PublicInboxArchiveError.batchTooLarge(
                commitOIDs.count
            )
        }

        let requests = commitOIDs.map {
            "\($0):m\n"
        }.joined()

        let result = try git.run(
            arguments: [
                "-C",
                epoch.repositoryURL.path,
                "cat-file",
                "--batch",
            ],
            standardInput: Data(requests.utf8)
        )

        return try CatFileBatchParser.parse(
            result.standardOutput,
            commitOIDs: commitOIDs
        )
    }
}

private struct GitProcess: Sendable {
    struct Result {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
    }

    func text(
        arguments: [String]
    ) throws -> String {
        let result = try run(
            arguments: arguments
        )

        guard let value = String(
            data: result.standardOutput,
            encoding: .utf8
        ) else {
            throw PublicInboxArchiveError
                .invalidGitOutput(
                    "git output was not UTF-8"
                )
        }

        return value
    }

    @discardableResult
    func run(
        arguments: [String],
        standardInput: Data? = nil,
        standardOutputURL: URL? = nil,
        acceptedStatuses: Set<Int32> = [0]
    ) throws -> Result {
        let process = Process()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/git"
        )
        process.arguments = arguments

        let temporaryDirectory =
            FileManager.default
            .temporaryDirectory

        let standardErrorURL =
            temporaryDirectory
            .appendingPathComponent(
                "nexus-kb-git-stderr-\(UUID().uuidString)"
            )

        try Data().write(
            to: standardErrorURL,
            options: .atomic
        )

        let standardErrorHandle =
            try FileHandle(
                forWritingTo: standardErrorURL
            )

        process.standardError =
            standardErrorHandle

        var standardInputURL: URL?
        var standardInputHandle: FileHandle?

        if let standardInput {
            let url =
                temporaryDirectory
                .appendingPathComponent(
                    "nexus-kb-git-stdin-\(UUID().uuidString)"
                )

            try standardInput.write(
                to: url,
                options: .atomic
            )

            let handle = try FileHandle(
                forReadingFrom: url
            )

            standardInputURL = url
            standardInputHandle = handle
            process.standardInput = handle
        }

        let standardOutputPipe: Pipe?
        let standardOutputHandle: FileHandle?

        if let standardOutputURL {
            guard
                FileManager.default.createFile(
                    atPath: standardOutputURL.path,
                    contents: nil
                )
            else {
                throw
                    PublicInboxArchiveError
                    .unableToCreateTemporaryFile(
                        standardOutputURL.path
                    )
            }

            let handle = try FileHandle(
                forWritingTo: standardOutputURL
            )

            standardOutputPipe = nil
            standardOutputHandle = handle
            process.standardOutput = handle
        } else {
            let pipe = Pipe()

            standardOutputPipe = pipe
            standardOutputHandle = nil
            process.standardOutput = pipe
        }

        defer {
            try? standardInputHandle?.close()
            try? standardOutputHandle?.close()
            try? standardErrorHandle.close()

            if let standardInputURL {
                try? FileManager.default.removeItem(
                    at: standardInputURL
                )
            }

            try? FileManager.default.removeItem(
                at: standardErrorURL
            )
        }

        try process.run()

        /*
         Read piped stdout while Git is running. stderr is
         directed to a regular file, so it cannot fill a pipe
         and deadlock Git while stdout is being consumed.
         */
        let outputData: Data

        if let standardOutputPipe {
            outputData =
                standardOutputPipe
                .fileHandleForReading
                .readDataToEndOfFile()
        } else {
            outputData = Data()
        }

        process.waitUntilExit()

        /*
         Close the parent-side write handles before reading
         their files. The child process has already exited.
         */
        try standardOutputHandle?.close()
        try standardErrorHandle.close()

        let errorData = try Data(
            contentsOf: standardErrorURL
        )

        let result = Result(
            status: process.terminationStatus,
            standardOutput: outputData,
            standardError: errorData
        )

        guard acceptedStatuses.contains(
            result.status
        ) else {
            throw PublicInboxArchiveError.gitFailed(
                arguments: arguments,
                status: result.status,
                message: String(
                    decoding: result.standardError,
                    as: UTF8.self
                ).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }

        return result
    }
}

private enum CatFileBatchParser {
    static func parse(
        _ data: Data,
        commitOIDs: [String]
    ) throws -> [PublicInboxCommit] {
        let bytes = [UInt8](data)
        var offset = 0
        var messages: [PublicInboxCommit] = []

        messages.reserveCapacity(
            commitOIDs.count
        )

        for commitOID in commitOIDs {
            let header = try readLine(
                bytes,
                offset: &offset
            )
            let fields = header.split(
                separator: " "
            )

            if fields.last == "missing" {
                throw PublicInboxArchiveError
                    .missingMessageBlob(commitOID)
            }

            guard fields.count == 3,
                  fields[1] == "blob",
                  let size = Int(fields[2]),
                  size >= 0,
                  offset + size <= bytes.count
            else {
                throw PublicInboxArchiveError
                    .invalidGitOutput(header)
            }

            let blobOID = String(fields[0])
            let rawMessage = Data(
                bytes[offset..<(offset + size)]
            )

            offset += size

            guard offset < bytes.count,
                  bytes[offset] == 10
            else {
                throw PublicInboxArchiveError
                    .invalidGitOutput(
                        "missing cat-file record terminator"
                    )
            }

            offset += 1

            messages.append(
                PublicInboxCommit(
                    commitOID: commitOID,
                    blobOID: blobOID,
                    rawMessage: rawMessage
                )
            )
        }

        return messages
    }

    private static func readLine(
        _ bytes: [UInt8],
        offset: inout Int
    ) throws -> String {
        guard offset < bytes.count,
              let newline = bytes[offset...]
                  .firstIndex(of: 10)
        else {
            throw PublicInboxArchiveError
                .invalidGitOutput(
                    "truncated cat-file header"
                )
        }

        let line = String(
            decoding: bytes[offset..<newline],
            as: UTF8.self
        )

        offset = newline + 1

        return line
    }
}
