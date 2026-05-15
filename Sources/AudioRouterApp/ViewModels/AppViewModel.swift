import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var snapshot: RoutingSnapshot
    @Published private(set) var errorMessage: String?
    @Published private(set) var tapProbeMessage: String?
    @Published private(set) var aggregateProbeMessage: String?
    @Published private(set) var captureProbeMessage: String?
    @Published private(set) var isDebugExpanded: Bool

    var onToggleSelection: (String) -> Void
    var onVolumeChange: (String, Double) -> Void
    var onMuteToggle: (String) -> Void
    var onModeChange: (RoutingMode) -> Void
    var onRefresh: () -> Void
    var onProbeTap: () -> Void
    var onProbeAggregate: () -> Void
    var onProbeCapture: () -> Void
    var onQuit: () -> Void

    init(
        settings: AppSettings,
        onToggleSelection: @escaping (String) -> Void,
        onVolumeChange: @escaping (String, Double) -> Void,
        onMuteToggle: @escaping (String) -> Void,
        onModeChange: @escaping (RoutingMode) -> Void,
        onRefresh: @escaping () -> Void,
        onProbeTap: @escaping () -> Void,
        onProbeAggregate: @escaping () -> Void,
        onProbeCapture: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.snapshot = RoutingSnapshot(mode: settings.preferredMode, devices: [], errorMessage: nil)
        self.errorMessage = nil
        self.tapProbeMessage = nil
        self.aggregateProbeMessage = nil
        self.captureProbeMessage = nil
        self.isDebugExpanded = false
        self.onToggleSelection = onToggleSelection
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        self.onModeChange = onModeChange
        self.onRefresh = onRefresh
        self.onProbeTap = onProbeTap
        self.onProbeAggregate = onProbeAggregate
        self.onProbeCapture = onProbeCapture
        self.onQuit = onQuit
    }

    func apply(snapshot: RoutingSnapshot) {
        self.snapshot = snapshot
        self.errorMessage = snapshot.errorMessage
    }

    func setErrorMessage(_ message: String) {
        errorMessage = message
    }

    func setTapProbeMessage(_ message: String?) {
        tapProbeMessage = message
    }

    func setAggregateProbeMessage(_ message: String?) {
        aggregateProbeMessage = message
    }

    func setCaptureProbeMessage(_ message: String?) {
        captureProbeMessage = message
    }

    func toggleDebugExpanded() {
        isDebugExpanded.toggle()
    }
}
