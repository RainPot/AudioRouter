import Combine
import Foundation

@MainActor
final class RoutingCoordinator {
    private let engine: AudioRoutingEngine
    private let snapshotSubject: CurrentValueSubject<RoutingSnapshot, Never>
    private let settingsSubject: CurrentValueSubject<AppSettings, Never>
    private var engineStatus: EngineStatus = .idle
    private var devices: [AudioOutputDevice] = []
    private var settings: AppSettings
    private var lastAppliedSnapshot: RoutingEngineSnapshot?

    var snapshotPublisher: AnyPublisher<RoutingSnapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    var settingsPublisher: AnyPublisher<AppSettings, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    init(settings: AppSettings, engine: AudioRoutingEngine) {
        self.settings = settings
        self.engine = engine
        let initialSnapshot = RoutingSnapshot(
            mode: settings.preferredMode,
            devices: [],
            errorMessage: nil,
            engineSummaryText: nil
        )
        self.snapshotSubject = CurrentValueSubject(initialSnapshot)
        self.settingsSubject = CurrentValueSubject(settings)
    }

    func updateEngineStatus(_ status: EngineStatus) {
        engineStatus = status
        publishViewState(errorMessage: nil)
    }

    func updateAvailableDevices(_ newDevices: [AudioOutputDevice]) {
        devices = newDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        mergeMissingDeviceStates()
        applyAndPublish()
    }

    func toggleSelection(for deviceID: String) {
        modifyState(for: deviceID) { state in
            state.isSelected.toggle()
        }
    }

    func setVolume(for deviceID: String, volume: Double) {
        modifyState(for: deviceID) { state in
            state.volume = min(max(volume, 0), 1)
        }
    }

    func toggleMute(for deviceID: String) {
        modifyState(for: deviceID) { state in
            state.isMuted.toggle()
        }
    }

    func setMode(_ mode: RoutingMode) {
        settings.preferredMode = mode
        settings.lastUpdatedAt = .now
        applyAndPublish()
    }

    private func mergeMissingDeviceStates() {
        for device in devices where settings.deviceStates[device.id] == nil {
            settings.deviceStates[device.id] = DeviceRoutingState(id: device.id)
        }
    }

    private func modifyState(for deviceID: String, mutate: (inout DeviceRoutingState) -> Void) {
        var state = settings.deviceStates[deviceID] ?? DeviceRoutingState(id: deviceID)
        mutate(&state)
        settings.deviceStates[deviceID] = state
        settings.lastUpdatedAt = .now
        applyAndPublish()
    }

    private func applyAndPublish() {
        let engineSnapshot = RoutingEngineSnapshot(
            mode: settings.preferredMode,
            selectedDevices: devices.compactMap { device in
                guard let state = settings.deviceStates[device.id], state.isSelected, device.isAvailable else {
                    return nil
                }
                return RoutingTarget(
                    deviceID: device.id,
                    volume: state.volume,
                    isMuted: state.isMuted,
                    manualDelayMilliseconds: state.manualDelayMilliseconds
                )
            }
        )

        var errorMessage: String?
        if engineSnapshot != lastAppliedSnapshot {
            do {
                try engine.apply(snapshot: engineSnapshot)
                lastAppliedSnapshot = engineSnapshot
            } catch {
                errorMessage = "应用路由失败：\(error.localizedDescription)"
            }
        }
        publishViewState(errorMessage: errorMessage)
        settingsSubject.send(settings)
    }

    private func publishViewState(errorMessage: String?) {
        let presentation = devices.map { device in
            let state = settings.deviceStates[device.id] ?? DeviceRoutingState(id: device.id)
            return DevicePresentation(
                id: device.id,
                name: device.name,
                kindName: device.kind.displayName,
                latencyHintName: device.latencyHint.displayName,
                isAvailable: device.isAvailable,
                isDefaultOutput: device.isDefaultOutput,
                supportsVolumeControl: device.supportsVolumeControl,
                isSelected: state.isSelected,
                volume: state.volume,
                isMuted: state.isMuted,
                estimatedLatencyText: Self.estimatedLatencyText(for: device),
                volumeControlHint: nil
            )
        }

        let snapshot = RoutingSnapshot(
            mode: settings.preferredMode,
            devices: presentation,
            errorMessage: errorMessage ?? engineStatus.lastErrorMessage,
            engineSummaryText: engineStatus.summaryText
        )
        snapshotSubject.send(snapshot)
    }

    private static func estimatedLatencyText(for device: AudioOutputDevice) -> String? {
        guard let milliseconds = device.metrics.estimatedOutputLatencyMilliseconds else {
            return nil
        }
        return String(format: "%.1f ms", milliseconds)
    }
}
