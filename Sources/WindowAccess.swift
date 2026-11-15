import ApplicationServices
import Foundation

final class WindowAccess {
    private let system = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(system, 0.25)
    }

    func window(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }

        for _ in 0..<12 {
            if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole {
                return isStandardWindow(element) ? element : nil
            }
            if let window = elementAttribute(element, kAXWindowAttribute) {
                return isStandardWindow(window) ? window : nil
            }
            guard let parent = elementAttribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        return nil
    }

    func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let origin = axValue(window, kAXPositionAttribute),
              AXValueGetValue(origin, .cgPoint, &position),
              let dimensions = axValue(window, kAXSizeAttribute),
              AXValueGetValue(dimensions, .cgSize, &size),
              position.x.isFinite, position.y.isFinite,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    func fit(_ window: AXUIElement, current: CGRect, desired: CGRect, in usable: CGRect) {
        guard isStandardWindow(window) else { return }
        var actual = current
        if current.size != desired.size {
            setSize(desired.size, of: window)
            if let resized = frame(of: window) {
                if resized.height == current.height {
                    actual = resized
                } else {
                    // Some apps tie height to width. Prefer leaving their size alone.
                    setSize(current.size, of: window)
                    actual = frame(of: window) ?? resized
                }
            }
        }

        var position = WindowFitPolicy.placeHorizontally(CGRect(origin: desired.origin, size: actual.size),
                                                         in: usable).origin
        if actual.origin != position, let value = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var value = size
        if let size = AXValueCreate(.cgSize, &value) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        }
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole &&
        attribute(window, "AXFullScreen") as? Bool != true
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
