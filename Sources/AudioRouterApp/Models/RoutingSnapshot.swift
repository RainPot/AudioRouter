import Foundation

struct RoutingSnapshot: Equatable {
    var mode: RoutingMode
    var devices: [DevicePresentation]
    var errorMessage: String?
    var engineSummaryText: String?

    var summaryText: String {
        if let engineSummaryText, !engineSummaryText.isEmpty {
            return engineSummaryText
        }
        let selectedCount = devices.filter(\.isSelected).count
        return "已选 \(selectedCount) 台设备"
    }
}

struct DevicePresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let kindName: String
    let latencyHintName: String
    let isAvailable: Bool
    let isDefaultOutput: Bool
    let supportsVolumeControl: Bool
    let isSelected: Bool
    let volume: Double
    let isMuted: Bool
    let estimatedLatencyText: String?
    let volumeControlHint: String?
}
