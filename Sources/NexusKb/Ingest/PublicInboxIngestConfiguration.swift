enum PublicInboxIngestConfiguration {
    static let defaultBatchSize = 10_000
    static let batchSizeRange = 1...10_000

    static let queueVisibilityTimeoutSeconds = 300
    static let queueHeartbeatIntervalSeconds = 60
}
