import Foundation

struct AppSettings: Codable, Equatable {
    var preferredMode: RoutingMode
    var deviceStates: [String: DeviceRoutingState]
    var lastUpdatedAt: Date

    static let defaultValue = AppSettings(
        preferredMode: .stableSync,
        deviceStates: [:],
        lastUpdatedAt: .now
    )
}

struct DeviceRoutingState: Codable, Equatable, Identifiable {
    let id: String
    var isSelected: Bool
    var volume: Double
    var isMuted: Bool
    var manualDelayMilliseconds: Double

    init(
        id: String,
        isSelected: Bool = false,
        volume: Double = 0.2,
        isMuted: Bool = false,
        manualDelayMilliseconds: Double = 0
    ) {
        self.id = id
        self.isSelected = isSelected
        self.volume = volume
        self.isMuted = isMuted
        self.manualDelayMilliseconds = manualDelayMilliseconds
    }
}

enum RoutingMode: String, Codable, CaseIterable {
    case stableSync
    case lowBuffer

    var displayName: String {
        switch self {
        case .stableSync:
            return "稳定同步"
        case .lowBuffer:
            return "低延迟"
        }
    }
}
