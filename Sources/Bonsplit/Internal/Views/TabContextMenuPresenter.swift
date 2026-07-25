import AppKit
import SwiftUI

struct TabContextMenuSnapshot {
    let tabId: UUID
    let state: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let forkConversationAvailabilityProvider: () -> TabContextForkConversationAvailability
    let forkConversationAvailabilityRefreshHandler: @MainActor () async -> Void
    let customItemsProvider: () -> [TabContextMenuItem]

    init(
        tabId: UUID,
        state: TabContextMenuState,
        moveDestinationsProvider: @escaping () -> [TabContextMoveDestination],
        forkConversationAvailabilityProvider: @escaping () -> TabContextForkConversationAvailability,
        forkConversationAvailabilityRefreshHandler: @escaping @MainActor () async -> Void = {},
        customItemsProvider: @escaping () -> [TabContextMenuItem] = { [] }
    ) {
        self.tabId = tabId
        self.state = state
        self.moveDestinationsProvider = moveDestinationsProvider
        self.forkConversationAvailabilityProvider = forkConversationAvailabilityProvider
        self.forkConversationAvailabilityRefreshHandler = forkConversationAvailabilityRefreshHandler
        self.customItemsProvider = customItemsProvider
    }
}

final class TabContextMenuActionTarget: NSObject {
    var onContextAction: ((TabContextAction) -> Void)?
    var onMoveDestination: ((String) -> Void)?
    var onCustomItem: ((String) -> Void)?

    @objc func performContextAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = TabContextAction(rawValue: rawValue) else {
            return
        }
        onContextAction?(action)
    }

    @objc func performMoveDestination(_ sender: NSMenuItem) {
        guard let destinationId = sender.representedObject as? String else { return }
        onMoveDestination?(destinationId)
    }

    @objc func performCustomItem(_ sender: NSMenuItem) {
        guard let itemId = sender.representedObject as? String else { return }
        onCustomItem?(itemId)
    }
}

@MainActor
final class TabContextMenu: NSMenu, NSMenuDelegate {
    let snapshot: TabContextMenuSnapshot
    private(set) var forkConversationAvailability: TabContextForkConversationAvailability
    private var refreshTask: Task<Void, Never>?

    init(
        snapshot: TabContextMenuSnapshot,
        forkConversationAvailability: TabContextForkConversationAvailability
    ) {
        self.snapshot = snapshot
        self.forkConversationAvailability = forkConversationAvailability
        super.init(title: "")
        autoenablesItems = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        reevaluateForkConversationAvailability()
    }

    func menuWillOpen(_ menu: NSMenu) {
        reevaluateForkConversationAvailability()
        guard forkConversationAvailability == .refreshing,
              refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            await self?.resolveRefreshingForkConversationAvailability()
            self?.refreshTask = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func resolveRefreshingForkConversationAvailability() async {
        guard forkConversationAvailability == .refreshing else { return }
        await snapshot.forkConversationAvailabilityRefreshHandler()
        guard !Task.isCancelled else { return }
        reevaluateForkConversationAvailability()
    }

    private func reevaluateForkConversationAvailability() {
        let availability = snapshot.forkConversationAvailabilityProvider()
        forkConversationAvailability = availability
        TabContextMenuBuilder.updateForkConversationAvailability(availability, in: self)
    }
}

struct TabContextMenuPresenter: NSViewRepresentable {
    let snapshot: TabContextMenuSnapshot
    let onContextAction: (TabContextAction) -> Void
    let onMoveDestination: (String) -> Void
    let onCustomItem: (String) -> Void

    @MainActor
    final class Coordinator {
        var snapshot: TabContextMenuSnapshot
        let actionTarget = TabContextMenuActionTarget()
        weak var view: NSView?
        var monitor: Any?

        init(snapshot: TabContextMenuSnapshot) {
            self.snapshot = snapshot
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func presentMenu(at point: NSPoint, in view: NSView) {
            let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: actionTarget)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(snapshot: snapshot)
        coordinator.actionTarget.onContextAction = onContextAction
        coordinator.actionTarget.onMoveDestination = onMoveDestination
        coordinator.actionTarget.onCustomItem = onCustomItem
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.view = view

        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak coordinator] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            guard let coordinator, let view = coordinator.view, let window = view.window else { return event }
            guard event.window === window else { return event }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return event }

            coordinator.presentMenu(at: point, in: view)
            return nil
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.snapshot = snapshot
        context.coordinator.actionTarget.onContextAction = onContextAction
        context.coordinator.actionTarget.onMoveDestination = onMoveDestination
        context.coordinator.actionTarget.onCustomItem = onCustomItem
    }
}
