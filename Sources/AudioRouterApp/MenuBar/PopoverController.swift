import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private let popover: NSPopover

    init<Content: View>(contentView: Content) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }

    func toggle(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}
