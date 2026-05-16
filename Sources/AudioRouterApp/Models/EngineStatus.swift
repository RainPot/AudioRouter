import Foundation

struct EngineStatus: Equatable {
    let isRunning: Bool
    let selectedDeviceCount: Int
    let callbackCount: Int
    let deliveredBufferCount: Int
    let totalCapturedBytes: UInt64
    let lastErrorMessage: String?

    static let idle = EngineStatus(
        isRunning: false,
        selectedDeviceCount: 0,
        callbackCount: 0,
        deliveredBufferCount: 0,
        totalCapturedBytes: 0,
        lastErrorMessage: nil
    )

    var summaryText: String {
        if isRunning {
            return "运行中 · 设备 \(selectedDeviceCount)"
        }
        return selectedDeviceCount > 0 ? "待启动 · 设备 \(selectedDeviceCount)" : "未启动"
    }
}
