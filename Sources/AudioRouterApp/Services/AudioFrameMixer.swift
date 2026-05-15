import AudioToolbox
import Foundation

struct MixedAudioChunk {
    let sequenceNumber: UInt64
    let frameCount: Int
    let bytesPerFrame: Int
    let channelCount: Int
    let sampleRate: Double
    let format: AudioStreamBasicDescription
    let payload: Data
}

final class AudioFrameMixer {
    func applyGain(to chunk: CapturedAudioChunk, volume: Double, isMuted: Bool) throws -> MixedAudioChunk {
        let clampedVolume = isMuted ? 0 : max(0, min(1, volume))
        guard clampedVolume != 1 else {
            return MixedAudioChunk(
                sequenceNumber: chunk.sequenceNumber,
                frameCount: chunk.frameCount,
                bytesPerFrame: chunk.bytesPerFrame,
                channelCount: chunk.channelCount,
                sampleRate: chunk.sampleRate,
                format: chunk.format,
                payload: chunk.payload
            )
        }

        let format = try PCMLinearFormatDescription(chunk.format)
        var payload = Data(chunk.payload)
        payload.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            for frameIndex in 0 ..< chunk.frameCount {
                for channelIndex in 0 ..< chunk.channelCount {
                    let offset = format.sampleByteOffset(frameIndex: frameIndex, channelIndex: channelIndex)
                    let sample = format.readSample(from: baseAddress, byteOffset: offset)
                    format.writeSample(sample * Float(clampedVolume), to: baseAddress, byteOffset: offset)
                }
            }
        }

        return MixedAudioChunk(
            sequenceNumber: chunk.sequenceNumber,
            frameCount: chunk.frameCount,
            bytesPerFrame: chunk.bytesPerFrame,
            channelCount: chunk.channelCount,
            sampleRate: chunk.sampleRate,
            format: chunk.format,
            payload: payload
        )
    }
}
