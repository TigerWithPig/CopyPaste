# CopyPaste

[English](README.md) | 简体中文

CopyPaste 是一个轻量的原生 macOS 剪贴板管理器。它常驻菜单栏，可以记录最近复制过的内容，并支持快速搜索、预览、置顶和重新粘贴到当前 App。

CopyPaste 使用 Objective-C 和 AppKit 构建，不依赖 Electron、SwiftUI 或第三方包。

## 功能

- 菜单栏剪贴板历史。
- 全局快捷键：`Command + Shift + V`。
- 支持记录文本、链接、图片和文件 URL。
- 支持搜索，并按内容类型筛选。
- 支持置顶常用内容。
- 支持使用 pinboard 整理内容。
- 支持预览选中的剪贴板内容。
- 支持将选中内容粘贴回当前 App。
- 支持按纯文本复制。
- 可忽略指定 App 的剪贴板内容，例如钥匙串或密码管理器。
- 支持 Apple Silicon 和 Intel Mac 的 universal build。

## 系统要求

- macOS 13.0 或更高版本。
- 自动粘贴功能需要开启无障碍权限。
- 只有从源码构建时才需要安装 Xcode Command Line Tools。

## 安装

前往 [Releases](../../releases) 下载最新版 `CopyPaste-installer.dmg`。

然后：

1. 打开 `CopyPaste-installer.dmg`。
2. 将 `CopyPaste.app` 拖入 `Applications`。
3. 从 `Applications` 启动 `CopyPaste`。
4. 如果 macOS 提示“无法验证开发者”或“来自身份不明的开发者”，可以右键点击 `CopyPaste.app`，选择 `打开`，然后确认。

当前项目的本地试用构建使用 ad-hoc 签名。如果发布版本尚未 notarize，macOS 首次打开时可能会要求你手动确认。

## 首次使用

CopyPaste 会显示在 macOS 菜单栏中。

使用方式：

1. 复制文本、链接、图片或文件。
2. 点击菜单栏里的 CopyPaste 图标，或按 `Command + Shift + V`。
3. 从历史记录中选择一个项目。
4. 将它粘贴到当前 App。

自动粘贴需要 macOS 无障碍权限。如果没有授权，CopyPaste 仍会把选中的内容放回系统剪贴板，你可以手动按 `Command + V` 粘贴。

## 无障碍权限

启用自动粘贴：

1. 打开 `系统设置`。
2. 进入 `隐私与安全性`。
3. 打开 `辅助功能`。
4. 启用 `CopyPaste`。

没有这个权限也可以使用 CopyPaste，只是自动粘贴功能会受限。

## 从源码构建

克隆仓库后运行：

```bash
cd apps/macos
./scripts/package-universal.sh
```

构建产物会生成在：

```text
apps/macos/outputs/CopyPaste.app
apps/macos/outputs/CopyPaste-universal.zip
```

创建 DMG 安装包：

```bash
cd apps/macos
./scripts/create-dmg.sh
```

DMG 会生成在：

```text
apps/macos/outputs/CopyPaste-installer.dmg
```

## 项目结构

```text
apps/macos/Sources/CopyPaste/  AppKit 源码
apps/macos/Resources/          Info.plist 和 App 图标
apps/macos/scripts/            构建、打包和图标脚本
apps/macos/outputs/            生成的 app、zip 和 dmg 文件
apps/macos/work/               本地临时文件或旧版本构建文件
```

`apps/macos/outputs/`、`apps/macos/.build/` 和 `apps/macos/work/` 已经被 git 忽略，不应该提交到源码仓库。安装包建议上传到 GitHub Releases。

## 隐私

CopyPaste 会把剪贴板历史保存在你的 Mac 本机。

本地数据文件路径：

```text
~/Library/Application Support/CopyPaste/library.json
```

CopyPaste 不需要服务器账号，也不会把剪贴板内容上传到远程服务。

因为剪贴板历史可能包含敏感内容，使用任何剪贴板管理器时都应尽量避免复制密码、恢复密钥、私有 token 或其他机密信息。你可以在 CopyPaste 设置中添加需要忽略的 App Bundle ID。

## 说明

CopyPaste 是一个原创的本地 AppKit 应用，未使用 Paste 的品牌、图标或专有素材。

## License

CopyPaste 基于 [MIT License](LICENSE) 开源发布。
