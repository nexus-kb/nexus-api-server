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

    func commitOIDs(
        after cursor: String?,
        through tip: String
    ) throws -> [String] {
        if let cursor {
            let result = try git.run(
                arguments: [
                    "-C",
                    epoch.repositoryURL.path,
                    "merge-base",
                    "--is-ancestor",
                    cursor,
                    tip,
                ],
                acceptedStatuses: [0, 1]
            )

            guard result.status == 0 else {
                throw PublicInboxArchiveError
                    .cursorIsNotAncestor(
                        cursor: cursor,
                        tip: tip
                    )
            }
        }

        let revision = cursor.map {
            "\($0)..\(tip)"
        } ?? tip

        let output = try git.text(
            arguments: [
                "-C",
                epoch.repositoryURL.path,
                "rev-list",
                "--reverse",
                "--first-parent",
                revision,
            ]
        )

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    func loadMessages(
        commitOIDs: [String]
    ) throws -> [PublicInboxCommit] {
        guard !commitOIDs.isEmpty else {
            return []
        }

        guard commitOIDs.count <= 500 else {
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

    func run(
        arguments: [String],
        standardInput: Data? = nil,
        acceptedStatuses: Set<Int32> = [0]
    ) throws -> Result {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/git"
        )
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        if let standardInput {
            let input = Pipe()
            process.standardInput = input

            try process.run()
            input.fileHandleForWriting.write(
                standardInput
            )
            try input.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        let outputData =
            standardOutput.fileHandleForReading
                .readDataToEndOfFile()

        let errorData =
            standardError.fileHandleForReading
                .readDataToEndOfFile()

        process.waitUntilExit()

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
