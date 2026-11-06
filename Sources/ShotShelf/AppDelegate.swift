import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

enum CaptureMode {
    case image // copy the picture
    case text  // copy the recognized text
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: GlassPanel!
    private let store = ShotStore()
    private var hotKeys: [HotKey] = []
    private var isCapturing = false
    private var lastPanelHide = Date.distantPast
    static let initialIconOffset: Double = 360

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        registerHotKeys()
        store.permissionGranted = CGPreflightScreenCaptureAccess()

        if !UserDefaults.standard.bool(forKey: "didLaunchBefore") {
            UserDefaults.standard.set(true, forKey: "didLaunchBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
    }

    // MARK: - Menu bar icon

    private func setupStatusItem() {
        // New status items land at the far left of the icon area, which on a notched MacBook
        // with many icons is behind the notch. Unless the user has moved it (⌘-drag),
        // start it near the right edge instead. The value is the distance from the right edge.
        let positionKey = "NSStatusItem Preferred Position Item-0"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(Self.initialIconOffset, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotShelf")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popUpMenu(fullMenu())
        } else {
            togglePanel()
        }
    }

    /// False when the icon sits behind the notch or was pushed out of a full menu bar.
    private var statusItemVisible: Bool {
        guard let window = statusItem.button?.window, let screen = window.screen else { return false }
        guard window.occlusionState.contains(.visible) else { return false }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // These rects may be screen-relative; normalize to global coordinates.
            let offset = abs(left.minX - screen.frame.minX) < 1 ? 0 : screen.frame.minX
            let notchMinX = left.maxX + offset, notchMaxX = right.minX + offset
            if window.frame.maxX > notchMinX && window.frame.minX < notchMaxX { return false }
        }
        return true
    }

    // MARK: - Panel

    private var panelActions: PanelActions {
        PanelActions(
            capture: { [weak self] mode in self?.capture(mode) },
            openFolder: { [weak self] in self?.openFolder() },
            showSettings: { [weak self] in self.map { $0.popUpMenu($0.moreMenu()) } },
            openPermissionSettings: { [weak self] in self?.openPermissionSettings() },
            relaunch: { [weak self] in self?.relaunch() }
        )
    }

    private func setupPanel() {
        let host = NSHostingView(rootView: PanelView(store: store, actions: panelActions))
        panel = GlassPanel(content: host, size: PanelView.size)
        panel.onHide = { [weak self] in self?.panelDidHide() }
    }

    // MARK: - Panel position (remembered once the user drags it)

    // Top-left corner, so a later size change keeps the panel's top where the user put it.
    private static let savedOriginKey = "panelTopLeft"
    /// Where showPanel put the panel; a different origin at hide time means the user moved it.
    private var placedOrigin: NSPoint?

    private func panelDidHide() {
        lastPanelHide = Date()
        let origin = panel.frame.origin
        if let placed = placedOrigin, hypot(origin.x - placed.x, origin.y - placed.y) > 1 {
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)),
                                      forKey: Self.savedOriginKey)
        }
    }

    /// The remembered spot, pulled back on screen; nil if never moved or its display is gone.
    private func savedOrigin(for size: NSSize) -> NSPoint? {
        guard let string = UserDefaults.standard.string(forKey: Self.savedOriginKey) else { return nil }
        let topLeft = NSPointFromString(string)
        let rect = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        let overlap = { (screen: NSScreen) in
            let r = screen.visibleFrame.intersection(rect)
            return r.isNull ? 0 : r.width * r.height
        }
        guard let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0
        else { return nil }
        let frame = screen.visibleFrame
        return NSPoint(x: min(max(rect.minX, frame.minX), frame.maxX - size.width),
                       y: min(max(rect.minY, frame.minY), frame.maxY - size.height))
    }

    @objc private func resetPanelPosition() {
        UserDefaults.standard.removeObject(forKey: Self.savedOriginKey)
        guard panel.isVisible else { return }
        let origin = anchoredOrigin(for: panel.frame.size)
        placedOrigin = origin
        panel.animator().setFrameOrigin(origin)
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.hide()
            return
        }
        // The click that just took focus away (and hid the panel) shouldn't reopen it.
        if Date().timeIntervalSince(lastPanelHide) < 0.25 { return }
        showPanel()
    }

    /// Where the user last dragged it; otherwise under the menu bar icon.
    private func showPanel() {
        store.permissionGranted = CGPreflightScreenCaptureAccess()
        let size = PanelView.size
        let origin = savedOrigin(for: size) ?? anchoredOrigin(for: size)
        placedOrigin = origin
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    /// Under the menu bar icon when it can be seen, else top-right of the screen with the mouse.
    private func anchoredOrigin(for size: NSSize) -> NSPoint {
        if statusItemVisible, let icon = statusItem.button?.window, let screen = icon.screen {
            let frame = screen.visibleFrame
            let x = min(max(icon.frame.midX - size.width / 2, frame.minX + 8), frame.maxX - size.width - 8)
            return NSPoint(x: x, y: frame.maxY - size.height - 6)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        return NSPoint(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 6)
    }

    // MARK: - Menus

    private func fullMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(to: menu, "截图", #selector(menuCaptureImage), key: "a")
        addItem(to: menu, "截图识字", #selector(menuCaptureText), key: "o")
        addItem(to: menu, "截图记录", #selector(menuShowPanel), key: "s")
        menu.addItem(.separator())
        addItem(to: menu, "打开截图文件夹", #selector(menuOpenFolder))
        appendSettings(to: menu)
        return menu
    }

    private func moreMenu() -> NSMenu {
        let menu = NSMenu()
        appendSettings(to: menu)
        return menu
    }

    private func appendSettings(to menu: NSMenu) {
        if UserDefaults.standard.string(forKey: Self.savedOriginKey) != nil {
            addItem(to: menu, "面板回到图标下方", #selector(resetPanelPosition))
        }
        let login = addItem(to: menu, "开机自动启动", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 ShotShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = [.option, .shift] }
        item.target = self
        menu.addItem(item)
        return item
    }

    private func popUpMenu(_ menu: NSMenu) {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button {
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func menuCaptureImage() { capture(.image) }
    @objc private func menuCaptureText() { capture(.text) }
    @objc private func menuShowPanel() { showPanel() }
    @objc private func menuOpenFolder() { openFolder() }

    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        let modifiers = optionKey | shiftKey
        let bindings: [(Int, String, () -> Void)] = [
            (kVK_ANSI_A, "⌥⇧A", { [weak self] in self?.capture(.image) }),
            (kVK_ANSI_O, "⌥⇧O", { [weak self] in self?.capture(.text) }),
            (kVK_ANSI_S, "⌥⇧S", { [weak self] in self?.togglePanel() }),
        ]
        var failed: [String] = []
        for (keyCode, label, handler) in bindings {
            if let key = HotKey(keyCode: keyCode, modifiers: modifiers, handler: handler) {
                hotKeys.append(key)
            } else {
                failed.append(label)
            }
        }
        if !failed.isEmpty {
            store.hotKeyWarning = "快捷键 \(failed.joined(separator: "、")) 被其他应用占用，可先用下方按钮"
        }
    }

    // MARK: - Capture

    func capture(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            store.permissionGranted = false
            showPanel()
            return
        }
        isCapturing = true
        let wasShown = panel.isVisible
        panel.hide()

        Task { @MainActor in
            defer { self.isCapturing = false }
            // Give the panel time to disappear so it isn't in the frozen frame.
            if wasShown { try? await Task.sleep(for: .milliseconds(200)) }
            let screens: [FrozenScreen]
            do {
                screens = try await ScreenGrabber.grabAll()
            } catch {
                Toast.shared.show("截图失败", detail: error.localizedDescription)
                return
            }
            guard !screens.isEmpty,
                  let outcome = await CaptureOverlay.run(screens, recognizeOnSelect: mode == .text)
            else { return }
            await self.handle(outcome)
        }
    }

    private func handle(_ outcome: CaptureOutcome) async {
        let (image, scale, recognize): (CGImage, CGFloat, Bool) = switch outcome {
        case .copyImage(let image, let scale): (image, scale, false)
        case .recognize(let image, let scale): (image, scale, true)
        }
        let url = store.newShotURL()
        guard ImageFile.writePNG(image, scale: scale, to: url) else {
            Toast.shared.show("截图保存失败", detail: store.folder.path)
            return
        }
        let shot = store.add(url: url, screenScale: Double(scale))
        let preview = Thumbnails.make(url, maxPixel: 160)

        if !recognize {
            Clipboard.copyImage(at: url)
            Toast.shared.show("已复制截图", image: preview)
        } else {
            let text = await store.text(for: shot)
            if text.isEmpty {
                Toast.shared.show("没有识别到文字", detail: "截图已存到记录里", image: preview)
            } else {
                Clipboard.copyText(text)
                let count = text.filter { !$0.isWhitespace }.count
                let firstLine = text.split(separator: "\n").first.map(String.init)
                Toast.shared.show("已复制 \(count) 字", detail: firstLine, image: preview)
            }
        }
    }

    // MARK: - Helpers

    private func openFolder() {
        panel.hide()
        NSWorkspace.shared.open(store.folder)
    }

    private func openPermissionSettings() {
        panel.hide()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Screen-recording permission only takes effect after a restart.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
