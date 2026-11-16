import Foundation

/// Controls the Qwen ASR systemd user service on the Mini PC over the existing SSH trust.
/// The service remains private: its HTTP port is still only reachable through the local tunnel.
actor RemoteQwenASRService {
    static let shared = RemoteQwenASRService()

    private let healthURL = URL(string: "http://127.0.0.1:8765/health")!
    private let healthMarker = "simultrans-qwen-sidecar"
    private let sshPath = "/usr/bin/ssh"
    private let host = ProcessInfo.processInfo.environment["SIMULTRANS_QWEN_SSH_HOST"] ?? "minipc"
    private let serviceName = "qwen3-asr.service"
    private var scheduledStop: Task<Void, Never>?

    func start() throws {
        scheduledStop?.cancel()
        scheduledStop = nil
        if isHealthy() { return }
        try runSSH(["systemctl", "--user", "start", serviceName], timeout: 20)
        try waitForHealth(timeout: 55)
    }

    /// Keep the model warm briefly so a quick restart does not pay the 8–12s load cost.
    func stop(afterDelay delay: TimeInterval = 300) {
        scheduledStop?.cancel()
        scheduledStop = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.performStop()
            } catch {
                return
            }
        }
    }

    func stopImmediately() {
        scheduledStop?.cancel()
        scheduledStop = nil
        performStop()
    }

    private func performStop() {
        try? runSSH(["systemctl", "--user", "stop", serviceName], timeout: 20)
    }

    private func runSSH(_ remoteArguments: [String], timeout: TimeInterval) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            host,
        ] + remoteArguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            throw RemoteQwenError.timedOut
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let rawOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            let detail = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RemoteQwenError.sshFailed(detail)
        }
    }

    private func waitForHealth(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isHealthy() { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw RemoteQwenError.notReady
    }

    private func isHealthy() -> Bool {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 1

        let semaphore = DispatchSemaphore(value: 0)
        let marker = healthMarker
        let isReady = RemoteQwenLockedValue(false)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let data,
                  let body = String(data: data, encoding: .utf8) else {
                return
            }
            isReady.set(body.contains(marker))
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.2)
        task.cancel()
        return isReady.get()
    }

    private enum RemoteQwenError: LocalizedError {
        case timedOut
        case notReady
        case sshFailed(String)

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "Timed out while contacting the Mini PC Qwen service."
            case .notReady:
                return "The Mini PC Qwen service did not become ready in time."
            case .sshFailed(let detail):
                return detail.isEmpty
                    ? "Could not control the Mini PC Qwen service over SSH."
                    : "Could not control the Mini PC Qwen service over SSH: \(detail)"
            }
        }
    }
}

private final class RemoteQwenLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
