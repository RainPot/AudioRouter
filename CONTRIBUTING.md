# Contributing

欢迎提交 Issue 和 Pull Request。

## 开发环境

- macOS 14.2+
- Xcode 15+ 或可用的 Swift 6 工具链

## 本地开发

```bash
swift build
swift test
```

如果要验证系统音频捕获，请优先使用打包后的 `.app`：

```bash
zsh scripts/package_app.sh
open .build/debug/AudioRouterApp.app
```

## 提交约定

- 尽量保持改动聚焦
- 新增功能或修复 bug 时，优先补充测试
- 提交前至少执行一次 `swift build` 和 `swift test`

## 反馈问题

提交 Issue 时建议附带：

- macOS 版本
- 输出设备类型
- 是否通过 `.app` 形式启动
- 是否已经授予系统音频录制权限
