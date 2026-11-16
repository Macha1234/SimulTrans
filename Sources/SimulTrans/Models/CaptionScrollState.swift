import Observation

@Observable @MainActor
final class CaptionScrollState {
    private(set) var followsLatest = true
    func userDidScroll() { followsLatest = false }
    func resume() { followsLatest = true }
}
