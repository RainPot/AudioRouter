import AppKit
import Combine
import Foundation

@MainActor
final class AppBootstrap {
    private let deviceService: AudioDeviceService
    private let settingsStore: SettingsStore
    private let routingEngine: AudioRoutingEngine
    private let routingCoordinator: RoutingCoordinator
    private let menuBarController: MenuBarController
    private let popoverController: PopoverController
    private let viewModel: AppViewModel
    private let tapProbeService: ProcessTapProbeService
    private let aggregateProbeService: AggregateDeviceProbeService
    private let captureProbeService: AudioCaptureProbeService
    private var cancellables: Set<AnyCancellable> = []

    init(
        deviceService: AudioDeviceService = AudioDeviceService(),
        settingsStore: SettingsStore? = nil,
        routingEngine: AudioRoutingEngine? = nil,
        tapProbeService: ProcessTapProbeService = ProcessTapProbeService(),
        aggregateProbeService: AggregateDeviceProbeService = AggregateDeviceProbeService(),
        captureProbeService: AudioCaptureProbeService = AudioCaptureProbeService()
    ) {
        self.deviceService = deviceService
        self.settingsStore = settingsStore ?? SettingsStore(fileURL: Self.defaultSettingsURL())
        let settings = (try? self.settingsStore.load()) ?? .defaultValue
        let resolvedEngine: AudioRoutingEngine
        if let routingEngine {
            resolvedEngine = routingEngine
        } else if #available(macOS 14.2, *) {
            resolvedEngine = LiveAudioRoutingEngine()
        } else {
            resolvedEngine = UnsupportedAudioRoutingEngine()
        }
        self.routingEngine = resolvedEngine
        self.routingCoordinator = RoutingCoordinator(settings: settings, engine: resolvedEngine)
        self.menuBarController = MenuBarController()
        self.tapProbeService = tapProbeService
        self.aggregateProbeService = aggregateProbeService
        self.captureProbeService = captureProbeService
        self.viewModel = AppViewModel(
            settings: settings,
            onToggleSelection: { _ in },
            onVolumeChange: { _, _ in },
            onMuteToggle: { _ in },
            onModeChange: { _ in },
            onRefresh: {},
            onProbeTap: {},
            onProbeAggregate: {},
            onProbeCapture: {},
            onQuit: {}
        )
        self.popoverController = PopoverController(
            contentView: MainPanelView(viewModel: viewModel)
        )

        wireActions()
        bind()
    }

    func start() {
        if Bundle.main.bundleURL.pathExtension != "app" {
            viewModel.setCaptureProbeMessage("当前是从裸可执行文件启动，系统音频捕获可能只会返回静音数据。请改用打包后的 AudioRouterApp.app 启动，并在系统权限弹窗中允许“系统音频录制”。")
        }
        menuBarController.configure(
            popoverController: popoverController,
            onRefresh: { [weak self] in
                self?.refreshDevices()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        refreshDevices()
        deviceService.startMonitoring()
    }

    func stop() {
        deviceService.stopMonitoring()
    }

    private func wireActions() {
        viewModel.onToggleSelection = { [weak self] deviceID in
            self?.routingCoordinator.toggleSelection(for: deviceID)
        }
        viewModel.onVolumeChange = { [weak self] deviceID, volume in
            self?.routingCoordinator.setVolume(for: deviceID, volume: volume)
        }
        viewModel.onMuteToggle = { [weak self] deviceID in
            self?.routingCoordinator.toggleMute(for: deviceID)
        }
        viewModel.onModeChange = { [weak self] mode in
            self?.routingCoordinator.setMode(mode)
        }
        viewModel.onRefresh = { [weak self] in
            self?.refreshDevices()
        }
        viewModel.onProbeTap = { [weak self] in
            self?.probeTap()
        }
        viewModel.onProbeAggregate = { [weak self] in
            self?.probeAggregate()
        }
        viewModel.onProbeCapture = { [weak self] in
            self?.probeCapture()
        }
        viewModel.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func bind() {
        deviceService.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.routingCoordinator.updateAvailableDevices(devices)
            }
            .store(in: &cancellables)

        routingCoordinator.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.viewModel.apply(snapshot: snapshot)
                self?.menuBarController.refresh(summary: snapshot.summaryText)
            }
            .store(in: &cancellables)

        routingEngine.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.routingCoordinator.updateEngineStatus(status)
            }
            .store(in: &cancellables)

        routingCoordinator.settingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else {
                    return
                }
                try? settingsStore.save(settings)
            }
            .store(in: &cancellables)
    }

    private func refreshDevices() {
        do {
            let devices = try deviceService.fetchOutputDevices()
            routingCoordinator.updateAvailableDevices(devices)
            viewModel.setErrorMessage("")
        } catch {
            viewModel.setErrorMessage("刷新设备失败：\(error.localizedDescription)")
        }
    }

    private func probeTap() {
        do {
            let message = try tapProbeService.probeGlobalStereoTap()
            viewModel.setTapProbeMessage(message)
            viewModel.setAggregateProbeMessage(nil)
            viewModel.setErrorMessage("")
        } catch {
            viewModel.setTapProbeMessage(nil)
            viewModel.setErrorMessage("Tap 探测失败：\(error.localizedDescription)")
        }
    }

    private func probeAggregate() {
        do {
            let message = try aggregateProbeService.probeTapAggregateChain()
            viewModel.setAggregateProbeMessage(message)
            viewModel.setErrorMessage("")
        } catch {
            viewModel.setAggregateProbeMessage(nil)
            viewModel.setErrorMessage("Aggregate 探测失败：\(error.localizedDescription)")
        }
    }

    private func probeCapture() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let message = try await captureProbeService.probeCaptureCallback()
                viewModel.setCaptureProbeMessage(message)
                viewModel.setErrorMessage("")
            } catch {
                viewModel.setCaptureProbeMessage(nil)
                viewModel.setErrorMessage("Capture 探测失败：\(error.localizedDescription)")
            }
        }
    }

    private static func defaultSettingsURL() -> URL {
        let rootURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return rootURL
            .appendingPathComponent("AudioRouter", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
