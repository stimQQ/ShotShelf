# ShotShelf

macOS 菜单栏截图小工具：截图自动进剪贴板，留在一个毛玻璃小面板里随时找回；截图时可以打码、识字（离线 OCR）。免费开源。

A tiny macOS menu bar screenshot tool: captures go straight to the clipboard and stay in a frosted-glass history panel. Mosaic redaction and offline OCR (Apple Vision) right in the capture toolbar. English and Chinese UI. Free and open source (MIT).

<p>
  <img src="docs/panel-light.png" width="300" alt="浅色模式的截图记录面板">
  <img src="docs/panel-dark.png" width="300" alt="深色模式的截图记录面板">
</p>

## 功能

- **截图不再找不到**：截完自动复制到剪贴板，同时存进记录面板，像聊天记录一样按天排列
- **截图时打码**：框选后点「打码」，拖出要遮住的地方就变成马赛克
- **截图时识字**：点「识字」把选区里的文字识别出来并复制，中英文混排也能认，全程离线
- **拖出去就能发**：记录里的图片可以直接拖到微信、桌面等地方
- **几乎没有存在感**：只在菜单栏有一个图标，不占程序坞；内存约 30 MB
- **中英文界面**：默认跟随系统语言，也可以在设置里随时切换，立即生效
- 全局快捷键不需要辅助功能权限；带刘海的 MacBook 上图标被挡住时，用快捷键也能打开面板

## 下载安装

需要 macOS 14 或更新版本，Apple 芯片和 Intel 芯片的 Mac 都能用。

1. 到 [Releases](https://github.com/stimQQ/ShotShelf/releases/latest) 下载最新的 `ShotShelf-x.y.z.dmg`
2. 打开 dmg，把 ShotShelf 拖进「应用程序」
3. 从「应用程序」里打开 ShotShelf，菜单栏右上角会出现一个取景框图标

安装包已用 Developer ID 签名并经过苹果公证，双击就能打开。

## 从源码构建

需要 Xcode 或 Command Line Tools（Swift 5.9+）：

```bash
git clone https://github.com/stimQQ/ShotShelf.git
cd ShotShelf
./build.sh                      # 产物在 build/ShotShelf.app
open build/ShotShelf.app        # 想常驻可以拖进「应用程序」文件夹
```

`build.sh` 会优先用本机钥匙串里的 Apple Development 证书签名，这样重新构建后录屏权限还在；没有证书时退回 ad-hoc 签名，
每次重新构建后都要在系统设置里把 ShotShelf 的开关关掉再打开一次。

## 第一次使用

第一次截图时，按面板上的提示在「系统设置 › 隐私与安全性 › 录屏与系统录音」里打开 ShotShelf，然后点面板里的「重新启动」。
macOS 15 可能还会弹窗询问是否允许 ShotShelf 直接访问屏幕，选允许即可。

## 用法

| 操作 | 结果 |
|---|---|
| `⌥⇧A` | 截图：框选后出现工具条，可以打码、识字，点「完成」复制图片 |
| `⌥⇧O` | 截图识字：框选后直接识别文字并复制，不出工具条 |
| `⌥⇧S` | 打开 / 关闭截图记录 |
| 点菜单栏图标 | 打开截图记录：点图片复制，拖出去发送 |
| 右键菜单栏图标 | 快捷菜单 |

截图界面（按下快捷键时屏幕会定格）：

- 拖动框选区域；不拖直接单击，会选中鼠标下面的整个窗口
- 选好后可以拖动选区、拖八个圆点调整大小
- **打码**：打开后在选区里拖动，框住的地方变成马赛克，`⌘Z` 撤销
- **识字**：识别选区里的文字并复制
- **完成**：复制图片，也可以按回车、`⌘C` 或双击选区
- `Esc` 取消；右键清掉当前选区重新选

截图记录面板：左上角打开截图文件夹，右上角齿轮是设置（语言 / Language、开机自动启动、退出）。拖顶部的小横条可以移动面板，它会记住位置。

截图后不会自动识别文字，只有点「识字」或在记录里点「复制文字」时才识别。

## 数据和隐私

- 截图存在 `~/Pictures/ShotShelf/`，记录索引在 `~/Library/Application Support/ShotShelf/index.json`
- 文字识别用的是系统自带的 Vision 框架，在本机完成
- 不联网，不收集任何数据

## 开发

```bash
swift build
.build/debug/ShotShelf --ocr some.png                                   # 打印识别结果
SHOTSHELF_DIR=/tmp/x .build/debug/ShotShelf --snapshot out.png a.png   # 离屏渲染记录面板
.build/debug/ShotShelf --preview 5 a.png                                # 在屏幕右上角显示几秒真实的毛玻璃面板
.build/debug/ShotShelf --grab /tmp/x                                    # 定格所有屏幕并测耗时
.build/debug/ShotShelf --overlay-snapshot out.png full-screen@2x.png    # 离屏渲染截图界面（带打码和工具条）
```

`SHOTSHELF_DIR` 指向一个临时目录，调试时就不会动到真实的截图记录。

发布安装包用 `./release.sh`：构建通用二进制、用 Developer ID 签名、提交苹果公证，产物是 `dist/ShotShelf-<版本>.dmg`。
需要钥匙串里有 Developer ID Application 证书，以及一个 notarytool 凭据（用法见脚本开头的注释）。
应用图标由 `swift tools/make-icon.swift` 生成。

## 许可证

[MIT](LICENSE)
