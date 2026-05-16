# Audio Router

<p align="center">
  <img src="docs/images/audio-router-screenshot.png" alt="Audio Router 界面截图" width="297">
</p>

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

## 系统要求

- macOS 14.2 或更高版本

## 安装

从 GitHub Release 下载最新的 `AudioRouter-*-macos.dmg`，打开后将 `Audio Router.app` 拖到 `Applications`。

当前公开包默认未使用 Developer ID 签名和 Apple 公证。首次打开如果被系统拦截，可以在 Finder 中右键应用并选择打开。若需要免安全提示的正式分发，需要配置 Apple Developer ID 签名和公证。

## 授权

第一次启动并开始捕获系统音频时，请允许：

- 系统音频录制

如果没有弹权限，可以去系统设置里检查对应授权状态。

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


## 贡献

欢迎提交 Issue 和 Pull Request。

开始贡献前请先阅读：

- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE)
