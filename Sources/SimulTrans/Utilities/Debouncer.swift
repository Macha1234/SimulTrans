import Foundation

actor Debouncer {
    private let delay: TimeInterval
    private var task: Task<Void, Never>?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func debounce(action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
