import Foundation

final class AudioFrameRingBuffer {
    private let lock = NSLock()
    private var chunks: [CapturedAudioChunk] = []
    private var lastSequenceNumber: UInt64?
    private let maxChunkCount: Int
    private let capacityFrames: Int
    private var sampleRate: Double = 0
    private var channelCount: Int = 0
    private var storage: [Float] = []
    private var writeFramePosition: Int64 = 0
    private var availableFrameCount: Int = 0

    init(maxChunkCount: Int = 512, capacityFrames: Int = 480_000) {
        self.maxChunkCount = maxChunkCount
        self.capacityFrames = capacityFrames
    }

    func append(_ chunk: CapturedAudioChunk) {
        guard let decodedSamples = try? decode(chunk: chunk) else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        if storage.isEmpty || sampleRate != chunk.sampleRate || channelCount != chunk.channelCount {
            sampleRate = chunk.sampleRate
            channelCount = chunk.channelCount
            storage = [Float](repeating: 0, count: capacityFrames * max(channelCount, 1))
            writeFramePosition = 0
            availableFrameCount = 0
            chunks.removeAll()
        }

        chunks.append(chunk)
        lastSequenceNumber = chunk.sequenceNumber
        if chunks.count > maxChunkCount {
            chunks.removeFirst(chunks.count - maxChunkCount)
        }

        let frameCount = decodedSamples.count / max(channelCount, 1)
        guard frameCount > 0 else {
            return
        }

        let framesToKeep = min(frameCount, capacityFrames)
        let startFrame = frameCount - framesToKeep
        for frameIndex in 0 ..< framesToKeep {
            let sourceFrame = startFrame + frameIndex
            let absoluteFrame = writeFramePosition + Int64(frameIndex)
            let destinationBase = storageFrameIndex(for: absoluteFrame) * channelCount
            let sourceBase = sourceFrame * channelCount
            storage.replaceSubrange(
                destinationBase ..< destinationBase + channelCount,
                with: decodedSamples[sourceBase ..< sourceBase + channelCount]
            )
        }

        writeFramePosition += Int64(framesToKeep)
        availableFrameCount = min(capacityFrames, availableFrameCount + framesToKeep)
    }

    func snapshot() -> [CapturedAudioChunk] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return chunks
    }

    func latestSequenceNumber() -> UInt64? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return lastSequenceNumber
    }

    func configuration() -> AudioFrameRingBufferConfiguration? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !storage.isEmpty, channelCount > 0, sampleRate > 0 else {
            return nil
        }
        return AudioFrameRingBufferConfiguration(
            sampleRate: sampleRate,
            channelCount: channelCount,
            oldestFramePosition: writeFramePosition - Int64(availableFrameCount),
            latestFramePosition: writeFramePosition
        )
    }

    func render(
        into output: UnsafeMutableBufferPointer<Float>,
        outputFrameCount: Int,
        outputChannelCount: Int,
        outputSampleRate: Double,
        preferredLeadFrameCount: Double,
        readPosition: inout Double?,
        volume: Float,
        isMuted: Bool
    ) -> Int {
        guard outputFrameCount > 0, outputChannelCount > 0 else {
            return 0
        }

        for index in output.indices {
            output[index] = 0
        }

        guard !isMuted, volume > 0 else {
            return 0
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        guard !storage.isEmpty, channelCount > 0, sampleRate > 0, availableFrameCount > 1 else {
            readPosition = nil
            return 0
        }

        let oldestFramePosition = Double(writeFramePosition - Int64(availableFrameCount))
        let latestFramePosition = Double(writeFramePosition)
        let minimumReadablePosition = oldestFramePosition
        let maximumReadablePosition = max(oldestFramePosition, latestFramePosition - 2)
        let desiredStartPosition = max(
            oldestFramePosition,
            latestFramePosition - max(preferredLeadFrameCount, 2)
        )

        if readPosition == nil {
            readPosition = desiredStartPosition
        } else if let currentReadPosition = readPosition,
                  currentReadPosition < minimumReadablePosition || currentReadPosition > latestFramePosition {
            readPosition = desiredStartPosition
        }

        guard var sourcePosition = readPosition else {
            return 0
        }

        sourcePosition = min(max(sourcePosition, minimumReadablePosition), maximumReadablePosition)
        let sourceStep = sampleRate / max(outputSampleRate, 1)
        var renderedFrameCount = 0

        for frameIndex in 0 ..< outputFrameCount {
            if sourcePosition + 1 >= latestFramePosition {
                break
            }

            let lowerFrame = Int64(floor(sourcePosition))
            let upperFrame = lowerFrame + 1
            let fraction = Float(sourcePosition - Double(lowerFrame))
            let destinationBase = frameIndex * outputChannelCount

            for channelIndex in 0 ..< outputChannelCount {
                let sourceChannelIndex: Int
                if channelCount == 1 {
                    sourceChannelIndex = 0
                } else if channelIndex < channelCount {
                    sourceChannelIndex = channelIndex
                } else {
                    sourceChannelIndex = channelIndex % channelCount
                }

                let lowerSample = sample(
                    at: lowerFrame,
                    channelIndex: sourceChannelIndex
                )
                let upperSample = sample(
                    at: upperFrame,
                    channelIndex: sourceChannelIndex
                )
                output[destinationBase + channelIndex] = (lowerSample + (upperSample - lowerSample) * fraction) * volume
            }

            sourcePosition += sourceStep
            renderedFrameCount += 1
        }

        readPosition = sourcePosition
        return renderedFrameCount
    }

    func clear() {
        lock.lock()
        chunks.removeAll()
        lastSequenceNumber = nil
        sampleRate = 0
        channelCount = 0
        storage.removeAll(keepingCapacity: false)
        writeFramePosition = 0
        availableFrameCount = 0
        lock.unlock()
    }

    private func decode(chunk: CapturedAudioChunk) throws -> [Float] {
        let format = try PCMLinearFormatDescription(chunk.format)
        var decoded = [Float](repeating: 0, count: chunk.frameCount * chunk.channelCount)
        try chunk.payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw PCMLinearCodecError.invalidFormat
            }

            for frameIndex in 0 ..< chunk.frameCount {
                for channelIndex in 0 ..< chunk.channelCount {
                    let offset = format.sampleByteOffset(frameIndex: frameIndex, channelIndex: channelIndex)
                    decoded[frameIndex * chunk.channelCount + channelIndex] = format.readSample(
                        from: baseAddress,
                        byteOffset: offset
                    )
                }
            }
        }
        return decoded
    }

    private func storageFrameIndex(for absoluteFrame: Int64) -> Int {
        let normalized = absoluteFrame % Int64(capacityFrames)
        return Int(normalized >= 0 ? normalized : normalized + Int64(capacityFrames))
    }

    private func sample(at absoluteFrame: Int64, channelIndex: Int) -> Float {
        let frameIndex = storageFrameIndex(for: absoluteFrame)
        return storage[frameIndex * channelCount + channelIndex]
    }
}

struct AudioFrameRingBufferConfiguration {
    let sampleRate: Double
    let channelCount: Int
    let oldestFramePosition: Int64
    let latestFramePosition: Int64
}
