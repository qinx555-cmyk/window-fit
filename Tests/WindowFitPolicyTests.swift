import CoreGraphics

@main
struct WindowFitPolicyTests {
    static func main() {
        // The connected displays: portrait is to the right and extends above the primary.
        let landscapeBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let portraitCocoa = CGRect(x: 1920, y: -459, width: 1080, height: 1920)
        let portraitBounds = Display.quartzRect(portraitCocoa, primaryTop: landscapeBounds.maxY)
        precondition(portraitBounds == CGRect(x: 1920, y: -381, width: 1080, height: 1920))
        let landscape = Display(id: 1, bounds: landscapeBounds, usable: CGRect(x: 0, y: 30, width: 1920, height: 1050))
        let portrait = Display(id: 2, bounds: portraitBounds, usable: portraitBounds)

        let wide = CGRect(x: 150, y: 100, width: 1550, height: 750)
        let wideGrab = CGPoint(x: 1350, y: 115)
        let mostlyOnLandscape = wide.offsetBy(dx: 800, dy: 40)
        expect("wide window is moved fully onto portrait, even if most of it stayed on landscape",
               WindowFitPolicy.targetFrame(before: wide, after: mostlyOnLandscape, grab: wideGrab,
                                           from: landscape, to: portrait),
               CGRect(x: 1920, y: 140, width: 1080, height: 750))

        let tall = CGRect(x: 2020, y: -330, width: 850, height: 1700)
        expect("vertical overflow alone leaves a window untouched",
               WindowFitPolicy.targetFrame(before: tall, after: tall.offsetBy(dx: -1000, dy: 70),
                                           grab: CGPoint(x: 2430, y: -315), from: portrait, to: landscape), nil)
        expect("horizontal adjustment preserves an oversized window's height and vertical position",
               WindowFitPolicy.targetFrame(before: tall, after: tall.offsetBy(dx: -700, dy: 70),
                                           grab: CGPoint(x: 2430, y: -315), from: portrait, to: landscape),
               CGRect(x: 1070, y: -260, width: 850, height: 1700))

        let small = CGRect(x: 200, y: 120, width: 650, height: 550)
        let smallGrab = CGPoint(x: 560, y: 135)
        expect("a fitting, fully visible window is left alone",
               WindowFitPolicy.targetFrame(before: small, after: small.offsetBy(dx: 1920, dy: 100),
                                           grab: smallGrab, from: landscape, to: portrait), nil)
        expect("a fitting window can be repositioned without resizing",
               WindowFitPolicy.targetFrame(before: small, after: small.offsetBy(dx: 2420, dy: 100),
                                           grab: smallGrab, from: landscape, to: portrait),
               CGRect(x: 2350, y: 220, width: 650, height: 550))
        expect("native resizing while moving still allows horizontal placement",
               WindowFitPolicy.targetFrame(before: wide, after: CGRect(x: 1750, y: 140, width: 1080, height: 700),
                                           grab: wideGrab, from: landscape, to: portrait),
               CGRect(x: 1920, y: 140, width: 1080, height: 700))
        expect("movement within one display does not trigger adjustment",
               WindowFitPolicy.targetFrame(before: wide, after: mostlyOnLandscape, grab: wideGrab,
                                           from: landscape, to: landscape), nil)
        expect("dragging content across displays does not trigger adjustment",
               WindowFitPolicy.targetFrame(before: wide, after: wide, grab: CGPoint(x: wide.midX, y: wide.midY),
                                           from: landscape, to: portrait), nil)
        expect("dragging a resize handle across displays does not trigger adjustment",
               WindowFitPolicy.targetFrame(before: wide, after: CGRect(x: 1100, y: 100, width: 1100, height: 750),
                                           grab: CGPoint(x: 151, y: wide.midY), from: landscape, to: portrait), nil)
        expect("an app-imposed minimum keeps the left side on the target",
               WindowFitPolicy.placeHorizontally(CGRect(x: 2250, y: 220, width: 1200, height: 500), in: portrait.usable),
               CGRect(x: 1920, y: 220, width: 1200, height: 500))

        let leftBounds = CGRect(x: -900, y: 160, width: 900, height: 1440)
        let left = Display(id: 3, bounds: leftBounds, usable: CGRect(x: -852, y: 190, width: 852, height: 1410))
        expect("negative origins and a side Dock are respected",
               WindowFitPolicy.targetFrame(before: wide, after: wide.offsetBy(dx: -1150, dy: 20),
                                           grab: CGPoint(x: 200, y: 120), from: landscape, to: left),
               CGRect(x: -852, y: 120, width: 852, height: 750))
        print("Window fit geometry: 12 checks passed")
    }

    static func expect(_ name: String, _ actual: CGRect?, _ expected: CGRect?) {
        precondition(actual == expected, "\(name): expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}
