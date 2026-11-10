import AppKit
import SwiftUI

/// Turns `DocumentModel.ItemAction`s into an AppKit or SwiftUI menu, so the files view, treemap
/// and selection list all show the same context menu.
@MainActor
enum MenuBuilder {
    static func nsMenu(_ actions: [DocumentModel.ItemAction]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            if action.isSeparator { menu.addItem(.separator()); continue }
            let item = ClosureMenuItem(title: action.title, handler: action.perform)
            item.isEnabled = action.isEnabled
            if let submenu = action.submenu { item.submenu = nsMenu(submenu) }
            menu.addItem(item)
        }
        return menu
    }

    @ViewBuilder
    static func swiftUIItems(_ actions: [DocumentModel.ItemAction]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
            if action.isSeparator {
                Divider()
            } else if let submenu = action.submenu {
                Menu(action.title) { AnyView(swiftUIItems(submenu)) }.disabled(!action.isEnabled)
            } else {
                Button(action.title) { action.perform?() }.disabled(!action.isEnabled)
            }
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler?() }
}
