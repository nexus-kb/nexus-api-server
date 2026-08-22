import Foundation
import Vapor

enum MaintenanceMode: String, Codable, Sendable {
    case full
    case incremental
}

enum MaintenanceRunKind: String, Codable, Sendable {
    case ingest
    case patchLineage
    case grokmirror
}

enum MaintenanceTrigger: String, Codable, Sendable {
    case `operator`
    case grokmirror
}

enum MaintenanceRunState: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
}

enum MaintenanceStageOperation: String, Codable, Sendable {
    case ingest
    case patchLineage
}

enum MaintenanceStageState: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

struct MaintenanceMailingList: Sendable {
    let id: Int64
    let name: String
    let archiveGroup: String
    let archivePath: String?
}

struct MaintenanceStageRecord: Sendable {
    let id: UUID
    let mailingListID: Int64
    let mailingListName: String
    let archiveGroup: String
    let archivePath: String?
    let position: Int32
    let operation: MaintenanceStageOperation
    let mode: MaintenanceMode
    let state: MaintenanceStageState
    let processedItems: Int64
    let totalItems: Int64?
    let currentEpoch: Int32?
    let resetCompleted: Bool
    let error: String?
    let startedAt: Date?
    let finishedAt: Date?
}

struct MaintenanceRunRecord: Sendable {
    let id: UUID
    let sequence: Int64
    let kind: MaintenanceRunKind
    let trigger: MaintenanceTrigger
    let state: MaintenanceRunState
    let error: String?
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let stages: [MaintenanceStageRecord]
}

struct MaintenanceStageView: Content {
    let id: UUID
    let mailingList: String
    let archiveGroup: String
    let operation: MaintenanceStageOperation
    let mode: MaintenanceMode
    let state: MaintenanceStageState
    let processedItems: Int64
    let totalItems: Int64?
    let currentEpoch: Int32?
    let error: String?
    let startedAt: Date?
    let finishedAt: Date?

    init(_ value: MaintenanceStageRecord) {
        id = value.id
        mailingList = value.mailingListName
        archiveGroup = value.archiveGroup
        operation = value.operation
        mode = value.mode
        state = value.state
        processedItems = value.processedItems
        totalItems = value.totalItems
        currentEpoch = value.currentEpoch
        error = value.error
        startedAt = value.startedAt
        finishedAt = value.finishedAt
    }
}

struct MaintenanceRunView: Content {
    let id: UUID
    let kind: MaintenanceRunKind
    let trigger: MaintenanceTrigger
    let state: MaintenanceRunState
    let error: String?
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let stages: [MaintenanceStageView]

    init(_ value: MaintenanceRunRecord) {
        id = value.id
        kind = value.kind
        trigger = value.trigger
        state = value.state
        error = value.error
        createdAt = value.createdAt
        startedAt = value.startedAt
        finishedAt = value.finishedAt
        stages = value.stages.map(MaintenanceStageView.init)
    }
}

struct MaintenanceRunListView: Content {
    let items: [MaintenanceRunView]
}
