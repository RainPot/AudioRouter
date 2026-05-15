# Audio Router

一个面向 macOS 的多设备音频输出菜单栏应用。

`Audio Router` 的目标是让系统正在播放的音频同时输出到多个物理设备，并支持每个设备单独调节音量，重点场景包括：

- 蓝牙耳机 + 有线耳机同时听
- 多个蓝牙耳机同时听
- 内建设备 + 外接设备同步输出

## 功能

- 同时选择多个输出设备
- 每个设备独立软件音量
- 每个设备独立静音
- 设备热插拔自动刷新
- 设备状态持久化
- 菜单栏常驻使用

## 当前实现

当前版本基于 Core Audio 的正式主链：

- `Process Tap` 捕获系统正在播放的音频
- 私有 aggregate device 驱动捕获回调
- 共享 PCM 环形缓冲保存实时音频帧
- 每个物理设备独立输出会话
- 每个设备独立软件增益

## 系统要求

- macOS 14.2 或更高版本

## 快速开始

### 1. 构建

```bash
cd audio_router
swift build
```

### 2. 打包并启动

系统音频捕获请优先使用 `.app` 启动，不要直接用裸可执行文件。

```bash
cd audio_router
zsh scripts/package_app.sh
open .build/debug/AudioRouterApp.app
```

### 3. 授权

第一次启动并开始捕获系统音频时，请允许：

- 系统音频录制

如果没有弹权限，可以去系统设置里检查对应授权状态。

## 测试

```bash
cd audio_router
swift test
```

## 项目结构

```text
audio_router/
├── Sources/AudioRouterApp
├── Tests/AudioRouterAppTests
├── Resources
├── scripts
├── docs
├── Package.swift
└── README.md
```

## 已知限制

- 当前仍是第一版底层实现
- 蓝牙与有线混合场景还没有做更精细的自动延迟补偿
- 更复杂的设备时钟漂移补偿仍待完善
- 某些非标准 PCM 输出设备还需要继续兼容

## 路线图

- 更完善的延迟补偿
- 更稳的断连恢复
- 更好的设备状态展示
- 更广的输出格式兼容

## 文档

- [产品方案](docs/产品方案.md)
- [技术方案](docs/技术方案.md)

## 贡献

欢迎提交 Issue 和 Pull Request。

开始贡献前请先阅读：

- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE)
