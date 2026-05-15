import CoreAudio
import Foundation

struct CapturedAudioChunk {
    let sequenceNumber: UInt64
    let frameCount: Int
    let bytesPerFrame: Int
    let channelCount: Int
    let sampleRate: Double
    let timestamp: UInt64
    let format: AudioStreamBasicDescription
    let payload: Data
}

protocol SystemAudioCaptureSessionDelegate: AnyObject {
    func captureSession(_ session: SystemAudioCaptureSession, didCapture chunk: CapturedAudioChunk)
    func captureSession(_ session: SystemAudioCaptureSession, didFail error: Error)
}

final class SystemAudioCaptureSession {
    weak var delegate: SystemAudioCaptureSessionDelegate?
    private let stateLock = NSLock()
    private let callbackQueue = DispatchQueue(label: "audio-router.capture-session")
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var callbackCount: Int = 0
    private var totalCapturedBytes: UInt64 = 0
    private var nextSequenceValue: UInt64 = 0
    private var tapUUID: UUID?
    private var tapFormat: AudioStreamBasicDescription?

    func start() throws {
        guard #available(macOS 14.2, *) else {
            throw CaptureSessionError.unsupportedSystem
        }

        stop()

        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [try Self.currentProcessObjectID()])
        let tapUUID = UUID()
        tap.name = "AudioRouter Capture Tap"
        tap.uuid = tapUUID
        tap.isPrivate = true
        tap.muteBehavior = .mutedWhenTapped

        var createdTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tap, &createdTapID)
        guard tapStatus == noErr, createdTapID != 0 else {
            throw CaptureSessionError.tapCreateFailed(tapStatus)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter Capture Aggregate",
            kAudioAggregateDeviceUIDKey: "audio-router.capture.\(tapUUID.uuidString)",
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID.uuidString,
                kAudioSubTapDriftCompensationKey: 1,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceIsPrivateKey: 1,
        ]

        var createdAggregateID: AudioObjectID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &createdAggregateID
        )
        guard aggregateStatus == noErr, createdAggregateID != 0 else {
            _ = AudioHardwareDestroyProcessTap(createdTapID)
            throw CaptureSessionError.aggregateCreateFailed(aggregateStatus)
        }

        let tapFormat = try Self.tapFormat(for: createdTapID)

        var createdIOProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            createdAggregateID,
            callbackQueue
        ) { [weak self] _, inputData, inputTime, _, _ in
            self?.handleInputData(inputData, inputTime: inputTime, format: tapFormat)
        }
        guard ioProcStatus == noErr, let createdIOProcID else {
            _ = AudioHardwareDestroyAggregateDevice(createdAggregateID)
            _ = AudioHardwareDestroyProcessTap(createdTapID)
            throw CaptureSessionError.ioProcCreateFailed(ioProcStatus)
        }

        let startStatus = AudioDeviceStart(createdAggregateID, createdIOProcID)
        guard startStatus == noErr else {
            _ = AudioDeviceDestroyIOProcID(createdAggregateID, createdIOProcID)
            _ = AudioHardwareDestroyAggregateDevice(createdAggregateID)
            _ = AudioHardwareDestroyProcessTap(createdTapID)
            throw CaptureSessionError.deviceStartFailed(startStatus)
        }

        stateLock.lock()
        self.tapID = createdTapID
        self.aggregateID = createdAggregateID
        self.ioProcID = createdIOProcID
        self.tapUUID = tapUUID
        self.tapFormat = tapFormat
        self.callbackCount = 0
        self.totalCapturedBytes = 0
        self.nextSequenceValue = 0
        stateLock.unlock()
    }

    func stop() {
        stateLock.lock()
        let aggregateID = self.aggregateID
        let ioProcID = self.ioProcID
        let tapID = self.tapID
        self.aggregateID = 0
        self.ioProcID = nil
        self.tapID = 0
        self.tapUUID = nil
        self.tapFormat = nil
        stateLock.unlock()

        if let ioProcID, aggregateID != 0 {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        if aggregateID != 0 {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if #available(macOS 14.2, *), tapID != 0 {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
    }

    func metrics() -> CaptureSessionMetrics {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }
        return CaptureSessionMetrics(
            callbackCount: callbackCount,
            totalCapturedBytes: totalCapturedBytes,
            format: tapFormat
        )
    }

    private func handleInputData(
        _ inputData: UnsafePointer<AudioBufferList>?,
        inputTime: UnsafePointer<AudioTimeStamp>?,
        format: AudioStreamBasicDescription
    ) {
        guard let inputData else {
            return
        }

        do {
            let chunk = try Self.makeChunk(
                from: inputData,
                inputTime: inputTime,
                format: format,
                sequenceNumber: nextSequenceNumber()
            )

            stateLock.lock()
            callbackCount += 1
            totalCapturedBytes += UInt64(chunk.payload.count)
            stateLock.unlock()

            delegate?.captureSession(self, didCapture: chunk)
        } catch {
            delegate?.captureSession(self, didFail: error)
        }
    }

    private func nextSequenceNumber() -> UInt64 {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }
        let value = nextSequenceValue
        nextSequenceValue += 1
        return value
    }

    private static func makeChunk(
        from bufferList: UnsafePointer<AudioBufferList>,
        inputTime: UnsafePointer<AudioTimeStamp>?,
        format: AudioStreamBasicDescription,
        sequenceNumber: UInt64
    ) throws -> CapturedAudioChunk {
        let formatDescription = try PCMLinearFormatDescription(format)
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard let firstBuffer = buffers.first else {
            throw CaptureSessionError.emptyBufferList
        }

        let frameCount = formatDescription.frameCount(for: firstBuffer)
        let channelCount = formatDescription.channelCount
        let bytesPerFrame = formatDescription.bytesPerFrame
        let payload: Data

        if formatDescription.isInterleaved {
            guard let mData = firstBuffer.mData, firstBuffer.mDataByteSize > 0 else {
                throw CaptureSessionError.emptyBufferData
            }
            payload = Data(bytes: mData, count: Int(firstBuffer.mDataByteSize))
        } else {
            var data = Data(count: frameCount * bytesPerFrame)
            data.withUnsafeMutableBytes { rawBuffer in
                guard let targetBase = rawBuffer.baseAddress else {
                    return
                }
                for frameIndex in 0 ..< frameCount {
                    for channelIndex in 0 ..< channelCount {
                        guard channelIndex < buffers.count else {
                            continue
                        }
                        let sourceBuffer = buffers[channelIndex]
                        guard let sourceBase = sourceBuffer.mData else {
                            continue
                        }
                        let sourceOffset = formatDescription.sampleByteOffset(
                            frameIndex: frameIndex,
                            channelIndex: 0
                        )
                        let targetOffset = frameIndex * bytesPerFrame + channelIndex * formatDescription.bytesPerChannel
                        memcpy(
                            targetBase.advanced(by: targetOffset),
                            sourceBase.advanced(by: sourceOffset),
                            formatDescription.bytesPerChannel
                        )
                    }
                }
            }
            payload = data
        }

        let timestamp = Self.timestampValue(from: inputTime)
        return CapturedAudioChunk(
            sequenceNumber: sequenceNumber,
            frameCount: frameCount,
            bytesPerFrame: bytesPerFrame,
            channelCount: channelCount,
            sampleRate: format.mSampleRate,
            timestamp: timestamp,
            format: format,
            payload: payload
        )
    }

    private static func timestampValue(from inputTime: UnsafePointer<AudioTimeStamp>?) -> UInt64 {
        guard let inputTime else {
            return DispatchTime.now().uptimeNanoseconds
        }
        let flags = inputTime.pointee.mFlags
        if flags.contains(.sampleTimeValid) {
            return UInt64(max(0, inputTime.pointee.mSampleTime.rounded()))
        }
        if flags.contains(.hostTimeValid) {
            return inputTime.pointee.mHostTime
        }
        return DispatchTime.now().uptimeNanoseconds
    }

    private static func currentProcessObjectID() throws -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var processObjectID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &dataSize,
            &processObjectID
        )
        guard status == noErr, processObjectID != 0 else {
            throw CaptureSessionError.processObjectLookupFailed(status)
        }
        return processObjectID
    }

    private static func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
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
            throw CaptureSessionError.tapFormatReadFailed(status)
        }
        return format
    }
}

struct CaptureSessionMetrics {
    let callbackCount: Int
    let totalCapturedBytes: UInt64
    let format: AudioStreamBasicDescription?
}

enum CaptureSessionError: LocalizedError {
    case unsupportedSystem
    case processObjectLookupFailed(OSStatus)
    case tapCreateFailed(OSStatus)
    case tapFormatReadFailed(OSStatus)
    case aggregateCreateFailed(OSStatus)
    case ioProcCreateFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case emptyBufferList
    case emptyBufferData

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "当前系统低于 macOS 14.2"
        case let .processObjectLookupFailed(status):
            return "查找当前进程音频对象失败：\(status)"
        case let .tapCreateFailed(status):
            return "创建系统捕获 Tap 失败：\(status)"
        case let .tapFormatReadFailed(status):
            return "读取 Tap 格式失败：\(status)"
        case let .aggregateCreateFailed(status):
            return "创建捕获 Aggregate Device 失败：\(status)"
        case let .ioProcCreateFailed(status):
            return "创建捕获 IOProc 失败：\(status)"
        case let .deviceStartFailed(status):
            return "启动捕获设备失败：\(status)"
        case .emptyBufferList:
            return "捕获回调没有音频缓冲"
        case .emptyBufferData:
            return "捕获回调音频数据为空"
        }
    }
}
