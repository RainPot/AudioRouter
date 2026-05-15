import CoreAudio
import Foundation

struct AudioCaptureProbeService {
    func probeCaptureCallback() async throws -> String {
        guard #available(macOS 14.2, *) else {
            throw AudioCaptureProbeError.unsupportedSystem
        }

        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tap.name = "AudioRouter Capture Probe Tap"
        tap.uuid = UUID()
        tap.isPrivate = true
        tap.muteBehavior = .unmuted

        var tapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tap, &tapID)
        guard tapStatus == noErr else {
            throw AudioCaptureProbeError.tapCreateFailed(tapStatus)
        }

        var aggregateID: AudioObjectID = 0
        var ioProcID: AudioDeviceIOProcID?
        let counter = CaptureCounter()

        defer {
            if let ioProcID {
                _ = AudioDeviceStop(aggregateID, ioProcID)
                _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
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
            kAudioAggregateDeviceNameKey: "AudioRouter Capture Probe Aggregate",
            kAudioAggregateDeviceUIDKey: "audio-router.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [subTap],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]

        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        )
        guard aggregateStatus == noErr else {
            throw AudioCaptureProbeError.aggregateCreateFailed(aggregateStatus)
        }

        let queue = DispatchQueue(label: "audio-router.capture-probe")
        let createIOStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateID,
            queue
        ) { _, inputData, _, _, _ in
            counter.record(bufferList: inputData)
        }
        guard createIOStatus == noErr, let ioProcID else {
            throw AudioCaptureProbeError.ioProcCreateFailed(createIOStatus)
        }

        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        guard startStatus == noErr else {
            throw AudioCaptureProbeError.deviceStartFailed(startStatus)
        }

        try await Task.sleep(for: .milliseconds(600))

        let snapshot = counter.snapshot()
        let callbackCount = snapshot.callbackCount
        let totalBytes = snapshot.totalBytes

        return "Capture 探测完成：收到 \(callbackCount) 次回调，累计 \(totalBytes) 字节音频数据"
    }
}

private final class CaptureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var callbackCount: Int = 0
    private var totalBytes: UInt64 = 0

    func record(bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        let bytes = buffers.reduce(UInt64(0)) { partial, buffer in
            partial + UInt64(buffer.mDataByteSize)
        }

        lock.lock()
        callbackCount += 1
        totalBytes += bytes
        lock.unlock()
    }

    func snapshot() -> CaptureSnapshot {
        lock.lock()
        defer {
            lock.unlock()
        }
        return CaptureSnapshot(callbackCount: callbackCount, totalBytes: totalBytes)
    }
}

private struct CaptureSnapshot {
    let callbackCount: Int
    let totalBytes: UInt64
}

enum AudioCaptureProbeError: LocalizedError {
    case unsupportedSystem
    case tapCreateFailed(OSStatus)
    case aggregateCreateFailed(OSStatus)
    case ioProcCreateFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "当前系统低于 macOS 14.2"
        case let .tapCreateFailed(status):
            return "创建 Process Tap 失败：\(status)"
        case let .aggregateCreateFailed(status):
            return "创建 Aggregate Device 失败：\(status)"
        case let .ioProcCreateFailed(status):
            return "创建 IOProc 失败：\(status)"
        case let .deviceStartFailed(status):
            return "启动 Aggregate Device 失败：\(status)"
        }
    }
}
