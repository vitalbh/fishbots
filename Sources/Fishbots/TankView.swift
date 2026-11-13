import AppKit
import MetalKit

/// The aquarium's window: it can take keys even without a title bar (widget mode).
final class TankWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TankView: MTKView {
    /// Widget mode: dragging the empty water moves the window (it has no title bar).
    var dragMovesWindow: (() -> Bool)?
    var onKey: ((String) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var hits: ((CGPoint) -> Bool)?
    var onRightClick: ((CGPoint, NSEvent) -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil), event)
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    /// The mouse left the water.
    var onLeave: (() -> Void)?
    override func mouseExited(with event: NSEvent) { onLeave?() }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        (hits?(p) == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func keyDown(with event: NSEvent) {
        // Tab / ⇧Tab, Return and Esc: moving through who needs you (see AppDelegate.nav)
        switch Int(event.keyCode) {
        case 48: onKey?(event.modifierFlags.contains(.shift) ? "⇤" : "⇥"); return
        case 36, 76: onKey?("↩"); return
        case 53: onKey?("⎋"); return
        default: break
        }
        if let c = event.charactersIgnoringModifiers?.lowercased() { onKey?(c) } else { super.keyDown(with: event) }
    }
    // a click counts on release, so it can be told from a drag; a double click knocks on the glass
    var onDrag: ((_ from: CGPoint, _ to: CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onKnock: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    private var downAt: CGPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        downAt = p
        dragging = false
        if event.clickCount == 2 { onKnock?(p) }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let d = downAt else { return }
        if !dragging && hypot(p.x - d.x, p.y - d.y) > 6 {
            if dragMovesWindow?() == true && hits?(d) != true { window?.performDrag(with: event); downAt = nil; return }
            dragging = true
        }
        if dragging { onDrag?(d, p) }
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if dragging { onDragEnd?() } else if event.clickCount < 2 { onClick?(p) }
        downAt = nil
        dragging = false
    }
    override func scrollWheel(with event: NSEvent) {
        onScroll?(convert(event.locationInWindow, from: nil), event.scrollingDeltaY)
    }
}

/// Text layer on top of Metal: fish names and the footer.
final class LabelsView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }
}
