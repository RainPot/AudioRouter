import CoreAudio
import Foundation

struct AggregateDeviceProbeService {
    func probeTapAggregateChain() throws -> String {
        guard #available(macOS 14.2, *) else {
            throw AggregateDeviceProbeError.unsupportedSystem
        }

        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tap.name = "AudioRouter Aggregate Probe Tap"
        tap.uuid = UUID()
        tap.isPrivate = true
        tap.muteBehavior = .unmuted

        var tapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tap, &tapID)
        guard tapStatus == noErr else {
            throw AggregateDeviceProbeError.tapCreateFailed(tapStatus)
        }

        var aggregateID: AudioObjectID = 0
        defer {
            if aggregateID != 0 {
                _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            _ = AudioHardwareDestroyProcessTap(tapID)
        }

        let subTap: [String: Any] = [
            kAudioSubTapUIDKey: tap.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: 1,
        ]

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter Aggregate Probe",
            kAudioAggregateDeviceUIDKey: "audio-router.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [subTap],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]

        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        )
        guard aggregateStatus == noErr else {
            throw AggregateDeviceProbeError.aggregateCreateFailed(aggregateStatus)
        }

        let format = try tapFormat(for: tapID)
        let sampleRate = String(format: "%.0f", format.mSampleRate)
        let channels = format.mChannelsPerFrame

        return "Aggregate 探测通过：Tap 和私有聚合设备可创建，格式 \(sampleRate) Hz / \(channels) ch"
    }

    @available(macOS 14.2, *)
    private func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &format
        )
        guard status == noErr else {
            throw AggregateDeviceProbeError.tapFormatReadFailed(status)
        }
        return format
    }
}

enum AggregateDeviceProbeError: LocalizedError {
    case unsupportedSystem
    case tapCreateFailed(OSStatus)
    case aggregateCreateFailed(OSStatus)
    case tapFormatReadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "当前系统低于 macOS 14.2"
        case let .tapCreateFailed(status):
            return "创建 Process Tap 失败：\(status)"
        case let .aggregateCreateFailed(status):
            return "创建 Aggregate Device 失败：\(status)"
        case let .tapFormatReadFailed(status):
            return "读取 Tap 格式失败：\(status)"
        }
    }
}
