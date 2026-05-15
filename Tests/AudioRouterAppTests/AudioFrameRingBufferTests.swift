import AudioToolbox
import Foundation
import Testing
@testable import AudioRouterApp

struct AudioFrameRingBufferTests {
    @Test
    func renderReturnsFramesAfterAppend() throws {
        let ringBuffer = AudioFrameRingBuffer(capacityFrames: 4_096)
        let frameCount = 512
        let channelCount = 2
        let bytesPerFrame = channelCount * MemoryLayout<Float>.size

        var format = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var samples = [Float](repeating: 0, count: frameCount * channelCount)
        for index in samples.indices {
            samples[index] = 0.25
        }

        let payload = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: UnsafeBufferPointer<UInt8>(
                start: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: buffer.count * MemoryLayout<Float>.size
            ))
        }

        let chunk = CapturedAudioChunk(
            sequenceNumber: 0,
            frameCount: frameCount,
            bytesPerFrame: bytesPerFrame,
            channelCount: channelCount,
            sampleRate: 48_000,
            timestamp: 0,
            format: format,
            payload: payload
        )

        ringBuffer.append(chunk)

        var output = [Float](repeating: 0, count: frameCount * channelCount)
        var readPosition: Double?
        let rendered = output.withUnsafeMutableBufferPointer { buffer in
            ringBuffer.render(
                into: buffer,
                outputFrameCount: frameCount,
                outputChannelCount: channelCount,
                outputSampleRate: 48_000,
                preferredLeadFrameCount: 120.0 / 1_000 * 48_000,
                readPosition: &readPosition,
                volume: 1,
                isMuted: false
            )
        }

        #expect(rendered > 0)
        #expect(output.contains { $0 != 0 })
        _ = format
    }
}
