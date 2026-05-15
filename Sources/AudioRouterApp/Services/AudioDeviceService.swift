import Combine
import CoreAudio
import Foundation

final class AudioDeviceService {
    private let devicesSubject = CurrentValueSubject<[AudioOutputDevice], Never>([])
    private let listenerQueue = DispatchQueue(label: "audio-router.device-listener")
    private var monitoredAddresses: [AudioObjectPropertyAddress] = []
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    var devicesPublisher: AnyPublisher<[AudioOutputDevice], Never> {
        devicesSubject.eraseToAnyPublisher()
    }

    func startMonitoring() {
        guard listenerBlock == nil else {
            publishCurrentDevices()
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.publishCurrentDevices()
        }
        listenerBlock = block

        let addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
        ]

        for var address in addresses {
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                block
            )
        }

        monitoredAddresses = addresses
        publishCurrentDevices()
    }

    func stopMonitoring() {
        guard let listenerBlock else {
            return
        }

        for var address in monitoredAddresses {
            _ = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerQueue,
                listenerBlock
            )
        }

        monitoredAddresses.removeAll()
        self.listenerBlock = nil
    }

    func fetchOutputDevices() throws -> [AudioOutputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        try checkStatus(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ))

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        try checkStatus(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ))

        return try deviceIDs.compactMap { deviceID in
            try makeDevice(from: deviceID)
        }
    }

    private func publishCurrentDevices() {
        let devices = (try? fetchOutputDevices()) ?? []
        devicesSubject.send(devices)
    }

    private func makeDevice(from deviceID: AudioDeviceID) throws -> AudioOutputDevice? {
        guard try outputChannelCount(for: deviceID) > 0 else {
            return nil
        }

        let defaultOutputID = (try? defaultOutputDeviceID()) ?? 0

        let uid = try stringProperty(
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        )

        let name = try stringProperty(
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        )

        let transportType = (try? uint32Property(
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        )) ?? 0

        let kind = AudioOutputDevice.kind(for: transportType)
        let supportsVolumeControl = supportsVolume(deviceID: deviceID)
        let metrics = DeviceLatencyMetrics(
            sampleRate: try? float64Property(
                selector: kAudioDevicePropertyNominalSampleRate,
                scope: kAudioObjectPropertyScopeGlobal,
                deviceID: deviceID
            ),
            bufferFrameSize: try? uint32Property(
                selector: kAudioDevicePropertyBufferFrameSize,
                scope: kAudioDevicePropertyScopeOutput,
                deviceID: deviceID
            ),
            deviceLatencyFrames: try? uint32Property(
                selector: kAudioDevicePropertyLatency,
                scope: kAudioDevicePropertyScopeOutput,
                deviceID: deviceID
            ),
            safetyOffsetFrames: try? uint32Property(
                selector: kAudioDevicePropertySafetyOffset,
                scope: kAudioDevicePropertyScopeOutput,
                deviceID: deviceID
            )
        )

        return AudioOutputDevice(
            id: uid,
            name: name,
            kind: kind,
            isAvailable: true,
            isDefaultOutput: deviceID == defaultOutputID,
            supportsVolumeControl: supportsVolumeControl,
            transportTypeRawValue: transportType,
            latencyHint: AudioOutputDevice.latencyHint(for: kind),
            metrics: metrics
        )
    }

    private func outputChannelCount(for deviceID: AudioDeviceID) throws -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        try checkStatus(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize))

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            pointer.deallocate()
        }

        try checkStatus(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, pointer))
        let bufferList = pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func defaultOutputDeviceID() throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        try checkStatus(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        ))
        return deviceID
    }

    private func stringProperty(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioDeviceID
    ) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        try checkStatus(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize))

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<UnsafeRawPointer>.alignment
        )
        defer {
            pointer.deallocate()
        }

        try checkStatus(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, pointer))
        let unmanaged = pointer.assumingMemoryBound(to: Unmanaged<CFString>?.self)
        guard let cfString = unmanaged.pointee?.takeUnretainedValue() as String? else {
            throw AudioDeviceServiceError.invalidPropertyType
        }
        return cfString
    }

    private func uint32Property(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioDeviceID
    ) throws -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        try checkStatus(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &value))
        return value
    }

    private func float64Property(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioDeviceID
    ) throws -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        try checkStatus(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &value))
        return value
    }

    private func supportsVolume(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        return AudioObjectHasProperty(deviceID, &propertyAddress)
    }

    private func checkStatus(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioDeviceServiceError.osStatus(status)
        }
    }
}

enum AudioDeviceServiceError: LocalizedError {
    case osStatus(OSStatus)
    case invalidPropertyType

    var errorDescription: String? {
        switch self {
        case let .osStatus(code):
            return "Core Audio 错误 \(code)"
        case .invalidPropertyType:
            return "设备属性类型无效"
        }
    }
}
