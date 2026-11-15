import AppKit
import ApplicationServices

@main
@MainActor
final class WindowFitApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct Drag {
        let window: AXUIElement
        let frame: CGRect
        let source: Display
        let grab: CGPoint
    }

    private let access = WindowAccess()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "打开辅助功能设置…", action: #selector(requestPermission), keyEquivalent: "")
    private var displays: [Display] = []
    private var monitor: Any?
    private var buttonTimer: Timer?
    private var permissionTimer: Timer?
    private var isPressed = false
    private var drag: Drag?
    private var gesture = 0
    private var paused = false

    static func main() {
        let application = NSApplication.shared
        let delegate = WindowFitApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "窗口随屏")
            if button.image == nil { button.title = "随屏" }
            button.toolTip = "窗口随屏"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(.separator())
        for item in [permissionItem, pauseItem] {
            item.target = self
            menu.addItem(item)
        }
        let quit = NSMenuItem(title: "退出窗口随屏", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        statusItem.menu = menu

        reloadDisplays()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadDisplays),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        stopWatching()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    @objc private func requestPermission() {
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        refresh()
    }

    @objc private func reloadDisplays() {
        let current = readDisplays()
        if current != displays {
            stopWatching()
            displays = current
        }
        refresh()
    }

    private func readDisplays() -> [Display] {
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        return screens.compactMap { screen -> Display? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return Display(id: number.uint32Value,
                           bounds: Display.quartzRect(screen.frame, primaryTop: primaryTop),
                           usable: Display.quartzRect(screen.visibleFrame, primaryTop: primaryTop))
        }
    }

    @objc private func refresh() {
        let trusted = AXIsProcessTrusted()
        permissionItem.isHidden = trusted
        pauseItem.isHidden = !trusted
        pauseItem.title = paused ? "继续" : "暂停"

        if !trusted {
            statusLine.title = "窗口随屏 · 等待辅助功能授权"
        } else if paused {
            statusLine.title = "窗口随屏 · 已暂停"
        } else if displays.count < 2 {
            statusLine.title = "窗口随屏 · 等待第二块屏幕"
        } else {
            statusLine.title = "窗口随屏 · 已启用"
        }

        if trusted, !paused, displays.count >= 2 {
            if buttonTimer == nil { startWatching() }
        } else if buttonTimer != nil {
            stopWatching()
        }
    }

    private func startWatching() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, let point = event.cgEvent?.location else { return }
            if event.type == .leftMouseDown {
                self.begin(at: point)
            } else {
                self.end(at: point)
            }
        }
        // Window Server may consume mouse-up when it owns a native title bar drag.
        // Read just the button state as a fallback, without monitoring keystrokes.
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(pollButton),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        buttonTimer = timer
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        buttonTimer?.invalidate()
        buttonTimer = nil
        isPressed = false
        drag = nil
        gesture += 1
    }

    @objc private func pollButton() {
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard down != isPressed, let point = CGEvent(source: nil)?.location else { return }
        if down { begin(at: point) } else { end(at: point) }
    }

    private func begin(at point: CGPoint) {
        guard !isPressed else { return }
        isPressed = true
        gesture += 1
        guard let source = displays.first(where: { $0.bounds.contains(point) }),
              let window = access.window(at: point),
              let frame = access.frame(of: window), frame.insetBy(dx: -2, dy: -2).contains(point) else { return }
        drag = Drag(window: window, frame: frame, source: source, grab: point)
    }

    private func end(at point: CGPoint) {
        guard isPressed else { return }
        isPressed = false
        defer { drag = nil }
        guard let drag, let target = displays.first(where: { $0.bounds.contains(point) }),
              drag.source.id != target.id else { return }

        let completedGesture = gesture
        // Let the system commit the drop before reading and writing the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self, self.gesture == completedGesture,
                  let target = self.readDisplays().first(where: { $0.id == target.id }),
                  let current = self.access.frame(of: drag.window),
                  let desired = WindowFitPolicy.targetFrame(before: drag.frame, after: current, grab: drag.grab,
                                                            from: drag.source, to: target) else { return }
            self.access.fit(drag.window, current: current, desired: desired, in: target.usable)
            if desired.width < current.width {
                self.retryWidth(of: drag.window, afterDrop: current, on: target.id, gesture: completedGesture)
            }
        }
    }

    private func retryWidth(of window: AXUIElement, afterDrop: CGRect, on displayID: CGDirectDisplayID, gesture: Int) {
        // Some apps keep their old width until the window has settled on the new display.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220)) { [weak self] in
            guard let self, self.gesture == gesture,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  let display = self.readDisplays().first(where: { $0.id == displayID }),
                  let current = self.access.frame(of: window),
                  current.width > display.usable.width,
                  abs(current.minX - display.usable.minX) <= 2,
                  abs(current.minY - afterDrop.minY) <= 1,
                  current.height == afterDrop.height else { return }

            let desired = CGRect(x: display.usable.minX, y: current.minY,
                                 width: display.usable.width, height: current.height)
            self.access.fit(window, current: current, desired: desired, in: display.usable)
        }
    }
}
