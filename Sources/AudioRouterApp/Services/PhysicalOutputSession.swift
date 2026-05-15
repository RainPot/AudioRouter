import CoreAudio
import Foundation

protocol PhysicalOutputSession {
    var deviceID: String { get }
    func start() throws
    func stop()
    func update(volume: Double, isMuted: Bool) throws
    func metrics() -> PhysicalOutputMetrics
}

final class CoreAudioPhysicalOutputSession: PhysicalOutputSession {
    let deviceID: String

    private let ringBuffer: AudioFrameRingBuffer
    private let stateLock = NSLock()
    private var hardwareDeviceID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var streamFormat: AudioStreamBasicDescription?
    private var callbackCount: Int = 0
    private var deliveredFrameCount: Int = 0
    private var readPosition: Double?
    private var volume: Float
    private var isMuted: Bool
    private let preferredLeadMilliseconds: Double

    init(
        deviceID: String,
        ringBuffer: AudioFrameRingBuffer,
        volume: Double,
        isMuted: Bool,
        preferredLeadMilliseconds: Double = 120
    ) {
        self.deviceID = deviceID
        self.ringBuffer = ringBuffer
        self.volume = Float(max(0, min(1, volume)))
        self.isMuted = isMuted
        self.preferredLeadMilliseconds = preferredLeadMilliseconds
    }

    deinit {
        stop()
    }

    func start() throws {
        stop()

        let hardwareDeviceID = try Self.deviceID(forUID: deviceID)
        let streamFormat = try Self.outputVirtualFormat(for: hardwareDeviceID)
        var createdIOProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            hardwareDeviceID,
            nil
        ) { [weak self] _, _, _, outputData, _ in
            self?.render(outputData: outputData, deviceFormat: streamFormat)
        }
        guard createStatus == noErr, let createdIOProcID else {
            throw PhysicalOutputSessionError.ioProcCreateFailed(deviceID, createStatus)
        }

        let startStatus = AudioDeviceStart(hardwareDeviceID, createdIOProcID)
        guard startStatus == noErr else {
            _ = AudioDeviceDestroyIOProcID(hardwareDeviceID, createdIOProcID)
            throw PhysicalOutputSessionError.deviceStartFailed(deviceID, startStatus)
        }

        stateLock.lock()
        self.hardwareDeviceID = hardwareDeviceID
        self.ioProcID = createdIOProcID
        self.streamFormat = streamFormat
        self.callbackCount = 0
        self.deliveredFrameCount = 0
        self.readPosition = nil
        stateLock.unlock()
    }

    func stop() {
        stateLock.lock()
        let hardwareDeviceID = self.hardwareDeviceID
        let ioProcID = self.ioProcID
        self.hardwareDeviceID = 0
        self.ioProcID = nil
        self.streamFormat = nil
        self.readPosition = nil
        stateLock.unlock()

        if let ioProcID, hardwareDeviceID != 0 {
            _ = AudioDeviceStop(hardwareDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(hardwareDeviceID, ioProcID)
        }
    }

    func update(volume: Double, isMuted: Bool) throws {
        stateLock.lock()
        self.volume = Float(max(0, min(1, volume)))
        self.isMuted = isMuted
        stateLock.unlock()
    }

    func metrics() -> PhysicalOutputMetrics {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }
        return PhysicalOutputMetrics(
            callbackCount: callbackCount,
            deliveredFrameCount: deliveredFrameCount
        )
    }

    private func render(
        outputData: UnsafeMutablePointer<AudioBufferList>?,
        deviceFormat: AudioStreamBasicDescription
    ) {
        guard let outputData else {
            return
        }

        do {
            let format = try PCMLinearFormatDescription(deviceFormat)
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard let firstBuffer = outputBuffers.first else {
                return
            }

            let outputFrameCount: Int
            if format.isInterleaved {
                outputFrameCount = Int(firstBuffer.mDataByteSize) / max(format.bytesPerFrame, 1)
            } else {
                outputFrameCount = Int(firstBuffer.mDataByteSize) / max(format.bytesPerChannel, 1)
            }
            guard outputFrameCount > 0 else {
                return
            }

            let totalSamples = outputFrameCount * format.channelCount
            var scratch = [Float](repeating: 0, count: totalSamples)

            stateLock.lock()
            let volume = self.volume
            let isMuted = self.isMuted
            var readPosition = self.readPosition
            stateLock.unlock()

            let renderedFrames = scratch.withUnsafeMutableBufferPointer { buffer in
                ringBuffer.render(
                    into: buffer,
                    outputFrameCount: outputFrameCount,
                    outputChannelCount: format.channelCount,
                    outputSampleRate: deviceFormat.mSampleRate,
                    preferredLeadFrameCount: preferredLeadMilliseconds / 1_000 * deviceFormat.mSampleRate,
                    readPosition: &readPosition,
                    volume: volume,
                    isMuted: isMuted
                )
            }

            Self.zeroOutputBuffers(outputBuffers)

            stateLock.lock()
            self.callbackCount += 1
            self.deliveredFrameCount += renderedFrames
            self.readPosition = readPosition
            stateLock.unlock()

            if format.isInterleaved {
                guard let destinationBase = firstBuffer.mData else {
                    return
                }
                for frameIndex in 0 ..< outputFrameCount {
                    for channelIndex in 0 ..< format.channelCount {
                        let offset = format.sampleByteOffset(frameIndex: frameIndex, channelIndex: channelIndex)
                        format.writeSample(
                            scratch[frameIndex * format.channelCount + channelIndex],
                            to: destinationBase,
                            byteOffset: offset
                        )
                    }
                }
                return
            }

            for channelIndex in 0 ..< outputBuffers.count {
                guard let destinationBase = outputBuffers[channelIndex].mData else {
                    continue
                }
                for frameIndex in 0 ..< outputFrameCount {
                    let sampleIndex = frameIndex * format.channelCount + min(channelIndex, format.channelCount - 1)
                    let byteOffset = format.sampleByteOffset(frameIndex: frameIndex, channelIndex: 0)
                    format.writeSample(
                        scratch[sampleIndex],
                        to: destinationBase,
                        byteOffset: byteOffset
                    )
                }
            }
        } catch {
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            Self.zeroOutputBuffers(outputBuffers)
            return
        }
    }

    private static func zeroOutputBuffers(_ outputBuffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in outputBuffers {
            guard let mData = buffer.mData, buffer.mDataByteSize > 0 else {
                continue
            }
            memset(mData, 0, Int(buffer.mDataByteSize))
        }
    }

    private static func deviceID(forUID uid: String) throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let qualifier = uid as CFString
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var audioDeviceID: AudioDeviceID = 0
        let status = withUnsafePointer(to: qualifier) { qualifierPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CFString>.size),
                qualifierPointer,
                &dataSize,
                &audioDeviceID
            )
        }
        guard status == noErr, audioDeviceID != 0 else {
            throw PhysicalOutputSessionError.deviceLookupFailed(uid, status)
        }
        return audioDeviceID
    }

    private static func outputVirtualFormat(for deviceID: AudioDeviceID) throws -> AudioStreamBasicDescription {
        let streamID = try firstOutputStreamID(for: deviceID)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyVirtualFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            streamID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &format
        )
        guard status == noErr else {
            throw PhysicalOutputSessionError.streamFormatReadFailed(deviceID, status)
        }
        return format
    }

    private static func firstOutputStreamID(for deviceID: AudioDeviceID) throws -> AudioObjectID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize >= MemoryLayout<AudioObjectID>.size else {
            throw PhysicalOutputSessionError.outputStreamLookupFailed(deviceID, sizeStatus)
        }

        let streamCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var streamIDs = [AudioObjectID](repeating: 0, count: streamCount)
        let readStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &streamIDs
        )
        guard readStatus == noErr, let streamID = streamIDs.first, streamID != 0 else {
            throw PhysicalOutputSessionError.outputStreamLookupFailed(deviceID, readStatus)
        }
        return streamID
    }
}

struct PhysicalOutputMetrics {
    let callbackCount: Int
    let deliveredFrameCount: Int
}

enum PhysicalOutputSessionError: LocalizedError {
    case deviceLookupFailed(String, OSStatus)
    case outputStreamLookupFailed(AudioDeviceID, OSStatus)
    case streamFormatReadFailed(AudioDeviceID, OSStatus)
    case ioProcCreateFailed(String, OSStatus)
    case deviceStartFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .deviceLookupFailed(uid, status):
            return "查找输出设备失败：\(uid) \(status)"
        case let .outputStreamLookupFailed(deviceID, status):
            return "查找输出流失败：\(deviceID) \(status)"
        case let .streamFormatReadFailed(deviceID, status):
            return "读取输出流格式失败：\(deviceID) \(status)"
        case let .ioProcCreateFailed(deviceID, status):
            return "创建输出 IOProc 失败：\(deviceID) \(status)"
        case let .deviceStartFailed(deviceID, status):
            return "启动输出设备失败：\(deviceID) \(status)"
        }
    }
}
