import Combine
import CoreAudio
import Foundation

protocol AudioRoutingEngine {
    var statusPublisher: AnyPublisher<EngineStatus, Never> { get }
    func apply(snapshot: RoutingEngineSnapshot) throws
}

struct RoutingEngineSnapshot: Equatable {
    let mode: RoutingMode
    let selectedDevices: [RoutingTarget]
}

struct RoutingTarget: Equatable {
    let deviceID: String
    let volume: Double
    let isMuted: Bool
    let manualDelayMilliseconds: Double
}

struct UnsupportedAudioRoutingEngine: AudioRoutingEngine {
    private let statusSubject = CurrentValueSubject<EngineStatus, Never>(.idle)

    var statusPublisher: AnyPublisher<EngineStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    func apply(snapshot: RoutingEngineSnapshot) throws {
        if snapshot.selectedDevices.isEmpty {
            statusSubject.send(.idle)
            return
        }
        throw LiveRoutingEngineError.unsupportedSystem
    }
}

final class LiveAudioRoutingEngine: AudioRoutingEngine {
    private let statusSubject = CurrentValueSubject<EngineStatus, Never>(.idle)
    private let stateLock = NSLock()
    private let ringBuffer = AudioFrameRingBuffer()
    private let captureSession = SystemAudioCaptureSession()
    private let mixer = AudioFrameMixer()
    private var outputSessions: [String: CoreAudioPhysicalOutputSession] = [:]
    private var currentSnapshot = RoutingEngineSnapshot(mode: .stableSync, selectedDevices: [])
    private var latestErrorMessage: String?

    var statusPublisher: AnyPublisher<EngineStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    init() {
        captureSession.delegate = self
    }

    func apply(snapshot: RoutingEngineSnapshot) throws {
        guard #available(macOS 14.2, *) else {
            throw LiveRoutingEngineError.unsupportedSystem
        }

        if snapshot.selectedDevices.isEmpty {
            stopAll()
            publishStatus()
            return
        }

        stateLock.lock()
        currentSnapshot = snapshot
        stateLock.unlock()

        do {
            try ensureCaptureStarted()
            try rebuildOutputSessions(for: snapshot)
            latestErrorMessage = nil
        } catch {
            latestErrorMessage = error.localizedDescription
            stopAll()
            publishStatus()
            throw error
        }

        publishStatus()
    }

    private func ensureCaptureStarted() throws {
        let metrics = captureSession.metrics()
        guard metrics.format == nil else {
            return
        }

        ringBuffer.clear()
        try captureSession.start()
    }

    private func rebuildOutputSessions(for snapshot: RoutingEngineSnapshot) throws {
        let desiredIDs = Set(snapshot.selectedDevices.map(\.deviceID))
        let existingIDs = Set(outputSessions.keys)

        for staleID in existingIDs.subtracting(desiredIDs) {
            outputSessions[staleID]?.stop()
            outputSessions.removeValue(forKey: staleID)
        }

        for target in snapshot.selectedDevices {
            if let session = outputSessions[target.deviceID] {
                try session.update(volume: target.volume, isMuted: target.isMuted)
                continue
            }

            let session = CoreAudioPhysicalOutputSession(
                deviceID: target.deviceID,
                ringBuffer: ringBuffer,
                volume: target.volume,
                isMuted: target.isMuted,
                preferredLeadMilliseconds: preferredLeadMilliseconds(for: snapshot.mode, target: target)
            )
            try session.start()
            outputSessions[target.deviceID] = session
        }
    }

    private func preferredLeadMilliseconds(for mode: RoutingMode, target: RoutingTarget) -> Double {
        let base: Double
        switch mode {
        case .stableSync:
            base = 160
        case .lowBuffer:
            base = 90
        }
        return max(20, base + target.manualDelayMilliseconds)
    }

    private func stopAll() {
        for session in outputSessions.values {
            session.stop()
        }
        outputSessions.removeAll()
        captureSession.stop()
        ringBuffer.clear()
        stateLock.lock()
        currentSnapshot = RoutingEngineSnapshot(mode: .stableSync, selectedDevices: [])
        stateLock.unlock()
        latestErrorMessage = nil
    }

    private func publishStatus() {
        let captureMetrics = captureSession.metrics()
        let outputMetrics = outputSessions.values.map { $0.metrics() }
        let totalDeliveredFrames = outputMetrics.reduce(0) { $0 + $1.deliveredFrameCount }
        let totalCallbackCount = outputMetrics.reduce(captureMetrics.callbackCount) { $0 + $1.callbackCount }

        let status = EngineStatus(
            isRunning: !outputSessions.isEmpty,
            selectedDeviceCount: outputSessions.count,
            callbackCount: totalCallbackCount,
            deliveredBufferCount: totalDeliveredFrames,
            totalCapturedBytes: captureMetrics.totalCapturedBytes,
            lastErrorMessage: latestErrorMessage
        )
        statusSubject.send(status)
    }
}

extension LiveAudioRoutingEngine: SystemAudioCaptureSessionDelegate {
    func captureSession(_ session: SystemAudioCaptureSession, didCapture chunk: CapturedAudioChunk) {
        ringBuffer.append(chunk)
        publishStatus()
    }

    func captureSession(_ session: SystemAudioCaptureSession, didFail error: Error) {
        latestErrorMessage = error.localizedDescription
        publishStatus()
    }
}

enum LiveRoutingEngineError: LocalizedError {
    case unsupportedSystem

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "当前系统不支持该模式"
        }
    }
}
