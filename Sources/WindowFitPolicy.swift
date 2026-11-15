import CoreGraphics

struct Display: Equatable {
    let id: CGDirectDisplayID
    let bounds: CGRect
    let usable: CGRect

    static func quartzRect(_ cocoa: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryTop - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }
}

enum WindowFitPolicy {
    static func targetFrame(before: CGRect, after: CGRect, grab: CGPoint,
                            from source: Display, to target: Display) -> CGRect? {
        guard source.id != target.id, !target.usable.isEmpty else { return nil }
        // A content drag leaves the frame in place. macOS can itself resize a
        // window on a cross-screen move, so only reject size changes from an edge grip.
        guard hypot(after.minX - before.minX, after.minY - before.minY) >= 4 else { return nil }
        let sizeChanged = abs(before.width - after.width) > 1 || abs(before.height - after.height) > 1
        if sizeChanged, !before.insetBy(dx: 10, dy: 10).contains(grab) { return nil }

        let size = CGSize(width: min(after.width, target.usable.width), height: after.height)
        let frame = placeHorizontally(CGRect(origin: after.origin, size: size), in: target.usable)
        return frame == after ? nil : frame
    }

    // With an app-imposed minimum width, align the left side of the window.
    static func placeHorizontally(_ frame: CGRect, in usable: CGRect) -> CGRect {
        let x = max(usable.minX, min(frame.minX, usable.maxX - frame.width))
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }
}
