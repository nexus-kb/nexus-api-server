//
//  PostgresService.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/11/26.
//

import PostgresNIO
import Vapor

private struct PostgresClientKey: StorageKey {
    typealias Value = PostgresClient
}

private struct PostgresClientLifecycle: LifecycleHandler {
    let runTask: Task<Void, Never>

    func shutdown(_ application: Application) {
        runTask.cancel()
    }

    func shutdownAsync(_ application: Application) async {
        runTask.cancel()
        await runTask.value
    }
}

private enum PostgresConfigurationError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case invalidPort(String)

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Missing required environment variable: \(name)"
        case .invalidPort(let value):
            return "Invalid POSTGRES_PORT value: \(value)"
        }
    }
}

private extension PostgresClient.Configuration {
    static func configFromEnvironment() throws -> Self {
        guard let username = Environment.get("POSTGRES_USER"),
              !username.isEmpty
        else {
            throw PostgresConfigurationError.missingEnvironmentVariable(
                "POSTGRES_USER"
            )
        }

        guard let password = Environment.get("POSTGRES_PASSWORD") else {
            throw PostgresConfigurationError.missingEnvironmentVariable(
                "POSTGRES_PASSWORD"
            )
        }

        guard let database = Environment.get("POSTGRES_DATABASE"),
              !database.isEmpty
        else {
            throw PostgresConfigurationError.missingEnvironmentVariable(
                "POSTGRES_DATABASE"
            )
        }

        let port: Int

        if let portValue = Environment.get("POSTGRES_PORT") {
            guard let parsedPort = Int(portValue),
                  (1...65_535).contains(parsedPort)
            else {
                throw PostgresConfigurationError.invalidPort(portValue)
            }

            port = parsedPort
        } else {
            port = 5_432
        }

        return .init(
            host: Environment.get("POSTGRES_HOST") ?? "127.0.0.1",
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
    }
}

extension Application {
    var postgres: PostgresClient {
        guard let client = storage[PostgresClientKey.self] else {
            fatalError("Postgres has not been configured")
        }

        return client
    }

    func configurePostgres() async throws {
        let client = PostgresClient(
            configuration: try .configFromEnvironment(),
            eventLoopGroup: eventLoopGroup,
            backgroundLogger: logger
        )

        let runTask = Task {
            await client.run()
        }

        await Task.yield()

        storage[PostgresClientKey.self] = client
        lifecycle.use(PostgresClientLifecycle(runTask: runTask))

        let rows = try await client.query(
            "SELECT 1",
            logger: logger
        )

        for try await _ in rows {}
    }
}

extension Request {
    var postgres: PostgresClient {
        application.postgres
    }
}
