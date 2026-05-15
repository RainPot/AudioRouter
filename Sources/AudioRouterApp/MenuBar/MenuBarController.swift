import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popoverController: PopoverController?
    private var onRefresh: (() -> Void)?
    private var onQuit: (() -> Void)?

    func configure(
        popoverController: PopoverController,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.popoverController = popoverController
        self.onRefresh = onRefresh
        self.onQuit = onQuit

        guard let button = statusItem.button else {
            return
        }

        button.image = Self.makeStatusItemImage()
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func refresh(summary: String) {
        statusItem.button?.toolTip = summary
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            popoverController?.toggle(relativeTo: sender.bounds, of: sender)
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        popoverController?.toggle(relativeTo: sender.bounds, of: sender)
    }

    @objc private func refreshDevices() {
        onRefresh?()
    }

    @objc private func quitApp() {
        onQuit?()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新设备", action: #selector(refreshDevices), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private static func makeStatusItemImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "speaker.wave.2.circle",
            accessibilityDescription: "Audio Router"
        )
        image?.isTemplate = true
        return image
    }
}
