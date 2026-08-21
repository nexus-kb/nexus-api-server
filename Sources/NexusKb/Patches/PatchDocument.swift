struct PatchDocument: Sendable, Equatable {
    let rawText: String
    let quotePrefix: String?
    let commitMessage: String
    let trailers: [PatchTrailer]
    let diffPreamble: [String]
    let files: [PatchChangedFile]
    let trailingLines: [String]
}

struct PatchTrailer: Sendable, Equatable {
    let key: String
    let value: String
    let rawLine: String
}

struct PatchChangedFile: Sendable, Equatable {
    let oldPath: String?
    let newPath: String?
    let operation: PatchFileOperation
    let diffHeader: String
    let headerLines: [String]
    let hunks: [PatchHunk]
    let trailingLines: [String]

    var path: String? {
        newPath ?? oldPath
    }
}

enum PatchFileOperation: String, Sendable, Equatable {
    case modified
    case added
    case deleted
    case renamed
    case copied
}

struct PatchHunk: Sendable, Equatable {
    let oldRange: PatchLineRange
    let newRange: PatchLineRange
    let sectionHeader: String?
    let rawHeader: String
    let lines: [PatchDiffLine]
}

struct PatchLineRange: Sendable, Equatable {
    let start: Int
    let count: Int
}

struct PatchDiffLine: Sendable, Equatable {
    let kind: PatchDiffLineKind
    let content: String
    let rawText: String
    let isInferred: Bool
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum PatchDiffLineKind: String, Sendable, Equatable {
    case context
    case addition
    case deletion
    case noNewlineMarker
}

struct PatchSymbol: Sendable, Equatable, Hashable {
    let name: String
    let kind: PatchSymbolKind
}

enum PatchSymbolKind: String, Sendable, Equatable, Hashable {
    case function
    case macro
    case type
}

struct PatchSymbolObservation: Sendable, Equatable {
    let symbol: PatchSymbol
    let relationship: PatchSymbolRelationship
    let fileIndex: Int
    let filePath: String
    let hunkIndex: Int
    let lineIndex: Int?
    let lineKind: PatchDiffLineKind?
    let evidenceMethod: PatchSymbolEvidenceMethod
    let confidence: Double
    let extractorVersion: String
}

enum PatchSymbolRelationship: String, Sendable, Equatable {
    case modifies
    case adds
    case deletes
    case calls
    case mentions
}

enum PatchSymbolEvidenceMethod: String, Sendable, Equatable {
    case hunkHeader
    case walkback
    case changedLineDefinition
    case changedLineCall
    case changedLineMention
}
