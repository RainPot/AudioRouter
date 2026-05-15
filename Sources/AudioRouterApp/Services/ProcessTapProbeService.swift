import CoreAudio
import Foundation

struct ProcessTapProbeService {
    func probeGlobalStereoTap() throws -> String {
        guard #available(macOS 14.2, *) else {
            throw ProcessTapProbeError.unsupportedSystem
        }

        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tap.name = "AudioRouter Probe"
        tap.uuid = UUID()
        tap.isPrivate = true
        tap.muteBehavior = .unmuted

        var tapID: AudioObjectID = 0
        let createStatus = AudioHardwareCreateProcessTap(tap, &tapID)
        guard createStatus == noErr else {
            throw ProcessTapProbeError.osStatus(createStatus)
        }

        let destroyStatus = AudioHardwareDestroyProcessTap(tapID)
        guard destroyStatus == noErr else {
            throw ProcessTapProbeError.osStatus(destroyStatus)
        }

        return "Tap 探测通过：当前系统支持创建 Process Tap"
    }
}

enum ProcessTapProbeError: LocalizedError {
    case unsupportedSystem
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "当前系统低于 macOS 14.2"
        case let .osStatus(status):
            return "Core Audio Tap 错误 \(status)"
        }
    }
}
