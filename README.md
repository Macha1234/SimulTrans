# SimulTrans

SimulTrans 是一个面向 macOS 15+ 的实时同传工具。它可以捕获系统音频或麦克风音频，使用 Apple 的语音识别能力生成字幕，再通过 `Translation` 框架实时翻译，并以悬浮窗方式展示原文和译文。

## 功能

- 支持系统音频和麦克风两种输入源
- 实时识别讲话内容并滚动显示
- 使用 Apple `Translation` 框架做本地翻译
- 提供悬浮字幕窗口和控制面板
- 支持保存导出会议记录

## 技术栈

- Swift Package Manager
- AppKit + SwiftUI
- `Speech`
- `ScreenCaptureKit`
- `Translation`

## 运行要求

- macOS 15 或更高版本
- Xcode 16 / Swift 6 工具链
- 首次运行时允许麦克风、语音识别、屏幕录制等系统权限
- 某些语言对首次使用时可能需要先下载系统语言包

## 项目结构

```text
.
├── AppTemplate/        # 打包时使用的 app bundle 模板
├── Sources/            # 主程序源码
├── build_and_run.sh    # 本地调试构建并直接启动 app
├── package.sh          # 构建 release 并生成 DMG
├── generate_icon.py    # 生成 AppIcon.icns
└── debug_ax.swift      # 辅助调试脚本（可选）
```

## 本地开发

直接编译：

```bash
swift build
```

构建并启动调试版：

```bash
./build_and_run.sh
```

如果你有自己的签名证书，可以在运行时指定：

```bash
SIGNING_ID="Apple Development: Your Name" ./build_and_run.sh
```

默认情况下脚本会使用 ad-hoc 签名，并把产物输出到 `dist/SimulTrans.app`。

## 打包 DMG

```bash
./package.sh
```

如果想覆盖版本号：

```bash
VERSION=1.0.1 ./package.sh
```

打包后的文件会出现在 `dist/` 目录下。

## 权限说明

根据输入源和运行方式，系统可能会要求以下权限：

- 麦克风
- 语音识别
- 屏幕录制

这些权限都需要在 macOS 的“系统设置 > 隐私与安全性”里授予。

## 备注

- `debug_ax.swift` 是辅助排查脚本，不是主程序运行所必需。
- 当前仓库只保留源码、模板资源和脚本；编译产物、DMG 和临时输出都被排除在 git 之外。
