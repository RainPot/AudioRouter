import SwiftUI

struct MainPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker("模式", selection: modeBinding) {
                ForEach(RoutingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let tapProbeMessage = viewModel.tapProbeMessage, !tapProbeMessage.isEmpty {
                Text(tapProbeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let aggregateProbeMessage = viewModel.aggregateProbeMessage, !aggregateProbeMessage.isEmpty {
                Text(aggregateProbeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let captureProbeMessage = viewModel.captureProbeMessage, !captureProbeMessage.isEmpty {
                Text(captureProbeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusPanel

            ScrollView {
                VStack(spacing: 10) {
                    if viewModel.snapshot.devices.isEmpty {
                        Text("未发现可用输出设备")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.snapshot.devices) { device in
                            DeviceRowView(
                                device: device,
                                onToggleSelection: { viewModel.onToggleSelection(device.id) },
                                onVolumeChange: { viewModel.onVolumeChange(device.id, $0) },
                                onMuteToggle: { viewModel.onMuteToggle(device.id) }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Button("刷新设备") {
                    viewModel.onRefresh()
                }
                Spacer()
                Button(viewModel.isDebugExpanded ? "收起调试" : "调试") {
                    viewModel.toggleDebugExpanded()
                }
                Button("退出") {
                    viewModel.onQuit()
                }
            }

            if viewModel.isDebugExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("调试探针")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("探测 Tap") {
                            viewModel.onProbeTap()
                        }
                        Button("探测 Aggregate") {
                            viewModel.onProbeAggregate()
                        }
                        Button("探测 Capture") {
                            viewModel.onProbeCapture()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio Router")
                .font(.headline)
            Text(viewModel.snapshot.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 10) {
            statusChip(title: "模式", value: viewModel.snapshot.mode.displayName)
            statusChip(title: "设备", value: "\(viewModel.snapshot.devices.filter(\.isSelected).count)")
            statusChip(
                title: "状态",
                value: viewModel.snapshot.engineSummaryText ?? "空闲"
            )
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var modeBinding: Binding<RoutingMode> {
        Binding(
            get: { viewModel.snapshot.mode },
            set: { viewModel.onModeChange($0) }
        )
    }
}

private struct DeviceRowView: View {
    let device: DevicePresentation
    let onToggleSelection: () -> Void
    let onVolumeChange: (Double) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Toggle(isOn: selectionBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(device.name)
                                .font(.body)
                            if device.isDefaultOutput {
                                Text("默认")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.14), in: Capsule())
                            }
                        }
                        Text("\(device.kindName) · \(device.latencyHintName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let estimatedLatencyText = device.estimatedLatencyText {
                            Text("估算链路延迟：\(estimatedLatencyText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let volumeControlHint = device.volumeControlHint {
                            Text(volumeControlHint)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!device.isAvailable)

                Spacer()

                Button(device.isMuted ? "取消静音" : "静音") {
                    onMuteToggle()
                }
                .buttonStyle(.borderless)
                .disabled(!device.isAvailable)
            }

            HStack {
                Text("音量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: volumeBinding, in: 0...1)
                    .disabled(!device.isAvailable || !device.isSelected)
                Text("\(Int(device.volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }

            if !device.isAvailable {
                Text("当前不可用，已保留配置")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { device.isSelected },
            set: { _ in onToggleSelection() }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { device.volume },
            set: { onVolumeChange($0) }
        )
    }
}
