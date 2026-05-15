import AudioToolbox
import Foundation

struct PCMLinearFormatDescription {
    let sampleRate: Double
    let channelCount: Int
    let bytesPerFrame: Int
    let bytesPerChannel: Int
    let bitsPerChannel: Int
    let isFloat: Bool
    let isInterleaved: Bool
    let isBigEndian: Bool

    init(_ asbd: AudioStreamBasicDescription) throws {
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw PCMLinearCodecError.unsupportedFormatID(asbd.mFormatID)
        }

        let flags = asbd.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        guard isFloat || isSignedInteger else {
            throw PCMLinearCodecError.unsupportedFormatFlags(flags)
        }

        let bitsPerChannel = Int(asbd.mBitsPerChannel)
        let bytesPerChannel = max(bitsPerChannel / 8, 1)
        let channelCount = Int(asbd.mChannelsPerFrame)
        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        guard channelCount > 0, bytesPerFrame > 0 else {
            throw PCMLinearCodecError.invalidFormat
        }

        self.sampleRate = asbd.mSampleRate
        self.channelCount = channelCount
        self.bytesPerFrame = bytesPerFrame
        self.bytesPerChannel = bytesPerChannel
        self.bitsPerChannel = bitsPerChannel
        self.isFloat = isFloat
        self.isInterleaved = flags & kAudioFormatFlagIsNonInterleaved == 0
        self.isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
    }

    func frameCount(for buffer: AudioBuffer) -> Int {
        if isInterleaved {
            return Int(buffer.mDataByteSize) / max(bytesPerFrame, 1)
        }
        return Int(buffer.mDataByteSize) / max(bytesPerChannel, 1)
    }

    func sampleByteOffset(frameIndex: Int, channelIndex: Int) -> Int {
        if isInterleaved {
            return frameIndex * bytesPerFrame + channelIndex * bytesPerChannel
        }
        return frameIndex * bytesPerChannel
    }

    func readSample(from base: UnsafeRawPointer, byteOffset: Int) -> Float {
        if isFloat {
            guard bitsPerChannel == 32 else {
                return 0
            }
            var raw: UInt32 = 0
            memcpy(&raw, base.advanced(by: byteOffset), 4)
            raw = isBigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
            return Float(bitPattern: raw)
        }

        switch bitsPerChannel {
        case 16:
            var raw: Int16 = 0
            memcpy(&raw, base.advanced(by: byteOffset), 2)
            raw = isBigEndian ? Int16(bigEndian: raw) : Int16(littleEndian: raw)
            return max(-1, Float(raw) / Float(Int16.max))
        case 24:
            let bytes = base.advanced(by: byteOffset).assumingMemoryBound(to: UInt8.self)
            let raw: Int32
            if isBigEndian {
                raw = Int32(bitPattern: UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2]))
            } else {
                raw = Int32(bitPattern: UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0]))
            }
            let signed = raw & 0x800000 != 0 ? raw | ~0x00FF_FFFF : raw
            return max(-1, Float(signed) / Float(0x7F_FFFF))
        case 32:
            var raw: Int32 = 0
            memcpy(&raw, base.advanced(by: byteOffset), 4)
            raw = isBigEndian ? Int32(bigEndian: raw) : Int32(littleEndian: raw)
            return max(-1, Float(raw) / Float(Int32.max))
        default:
            return 0
        }
    }

    func writeSample(_ sample: Float, to base: UnsafeMutableRawPointer, byteOffset: Int) {
        let clamped = max(-1, min(1, sample))

        if isFloat {
            guard bitsPerChannel == 32 else {
                return
            }
            var raw = clamped.bitPattern
            raw = isBigEndian ? raw.bigEndian : raw.littleEndian
            memcpy(base.advanced(by: byteOffset), &raw, 4)
            return
        }

        switch bitsPerChannel {
        case 16:
            var raw = Int16((clamped * Float(Int16.max)).rounded())
            raw = isBigEndian ? raw.bigEndian : raw.littleEndian
            memcpy(base.advanced(by: byteOffset), &raw, 2)
        case 24:
            let scaled = Int32((clamped * Float(0x7F_FFFF)).rounded())
            let bytes = base.advanced(by: byteOffset).assumingMemoryBound(to: UInt8.self)
            if isBigEndian {
                bytes[0] = UInt8((scaled >> 16) & 0xFF)
                bytes[1] = UInt8((scaled >> 8) & 0xFF)
                bytes[2] = UInt8(scaled & 0xFF)
            } else {
                bytes[0] = UInt8(scaled & 0xFF)
                bytes[1] = UInt8((scaled >> 8) & 0xFF)
                bytes[2] = UInt8((scaled >> 16) & 0xFF)
            }
        case 32:
            var raw = Int32((clamped * Float(Int32.max)).rounded())
            raw = isBigEndian ? raw.bigEndian : raw.littleEndian
            memcpy(base.advanced(by: byteOffset), &raw, 4)
        default:
            break
        }
    }
}

enum PCMLinearCodecError: LocalizedError {
    case unsupportedFormatID(UInt32)
    case unsupportedFormatFlags(UInt32)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormatID(formatID):
            return "不支持的 PCM FormatID：\(formatID)"
        case let .unsupportedFormatFlags(flags):
            return "不支持的 PCM FormatFlags：\(flags)"
        case .invalidFormat:
            return "PCM 格式无效"
        }
    }
}
