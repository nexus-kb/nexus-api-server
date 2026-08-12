//
//  HelloJob.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/12/26.
//

import Queues

struct HelloJob: AsyncJob {
    struct Payload: Codable, Sendable {}

    func dequeue(
        _ context: QueueContext,
        _ payload: Payload
    ) async throws {
        context.logger.info("Hello")
    }
}
