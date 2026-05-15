import Foundation
import Testing
@testable import AudioRouterApp

struct SettingsStoreTests {
    @Test
    func roundTripSettings() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: fileURL)

        let settings = AppSettings(
            preferredMode: .lowBuffer,
            deviceStates: [
                "device-1": DeviceRoutingState(
                    id: "device-1",
                    isSelected: true,
                    volume: 0.5,
                    isMuted: false,
                    manualDelayMilliseconds: 12
                )
            ],
            lastUpdatedAt: .now
        )

        try store.save(settings)
        let loaded = try store.load()

        #expect(loaded.preferredMode == RoutingMode.lowBuffer)
        #expect(loaded.deviceStates["device-1"]?.isSelected == true)
        #expect(loaded.deviceStates["device-1"]?.volume == 0.5)
    }
}
