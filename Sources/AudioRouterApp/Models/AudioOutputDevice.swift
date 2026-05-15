import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let kind: AudioDeviceKind
    let isAvailable: Bool
    let isDefaultOutput: Bool
    let supportsVolumeControl: Bool
    let transportTypeRawValue: UInt32
    let latencyHint: LatencyHint
    let metrics: DeviceLatencyMetrics

    init(
        id: String,
        name: String,
        kind: AudioDeviceKind,
        isAvailable: Bool = true,
        isDefaultOutput: Bool = false,
        supportsVolumeControl: Bool = false,
        transportTypeRawValue: UInt32 = 0,
        latencyHint: LatencyHint,
        metrics: DeviceLatencyMetrics = .empty
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isAvailable = isAvailable
        self.isDefaultOutput = isDefaultOutput
        self.supportsVolumeControl = supportsVolumeControl
        self.transportTypeRawValue = transportTypeRawValue
        self.latencyHint = latencyHint
        self.metrics = metrics
    }
}

struct DeviceLatencyMetrics: Equatable, Codable {
    let sampleRate: Double?
    let bufferFrameSize: UInt32?
    let deviceLatencyFrames: UInt32?
    let safetyOffsetFrames: UInt32?

    static let empty = DeviceLatencyMetrics(
        sampleRate: nil,
        bufferFrameSize: nil,
        deviceLatencyFrames: nil,
        safetyOffsetFrames: nil
    )

    var estimatedOutputLatencyMilliseconds: Double? {
        guard
            let sampleRate,
            sampleRate > 0
        else {
            return nil
        }

        let totalFrames = Double(bufferFrameSize ?? 0)
            + Double(deviceLatencyFrames ?? 0)
            + Double(safetyOffsetFrames ?? 0)
        guard totalFrames > 0 else {
            return nil
        }
        return totalFrames / sampleRate * 1_000
    }
}

enum AudioDeviceKind: String, Codable {
    case builtIn
    case bluetooth
    case usb
    case hdmi
    case airPlay
    case aggregate
    case unknown

    var displayName: String {
        switch self {
        case .builtIn:
            return "内建"
        case .bluetooth:
            return "蓝牙"
        case .usb:
            return "USB"
        case .hdmi:
            return "HDMI"
        case .airPlay:
            return "AirPlay"
        case .aggregate:
            return "聚合"
        case .unknown:
            return "未知"
        }
    }
}

enum LatencyHint: String, Codable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:
            return "低延迟"
        case .medium:
            return "中延迟"
        case .high:
            return "高延迟"
        }
    }
}

extension AudioOutputDevice {
    static func kind(for transportType: UInt32) -> AudioDeviceKind {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeHDMI:
            return .hdmi
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        default:
            return .unknown
        }
    }

    static func latencyHint(for kind: AudioDeviceKind) -> LatencyHint {
        switch kind {
        case .builtIn, .usb, .hdmi:
            return .low
        case .aggregate, .unknown:
            return .medium
        case .bluetooth, .airPlay:
            return .high
        }
    }
}
