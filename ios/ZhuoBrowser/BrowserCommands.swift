import SwiftUI

struct BrowserCommandActions {
    let canReopenTab: Bool
    let canReload: Bool
    let canFind: Bool
    let focusAddress: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Void
    let reopenTab: () -> Void
    let nextTab: () -> Void
    let previousTab: () -> Void
    let reload: () -> Void
    let find: () -> Void
}

private struct BrowserCommandActionsKey: FocusedValueKey {
    typealias Value = BrowserCommandActions
}

extension FocusedValues {
    var browserCommandActions: BrowserCommandActions? {
        get { self[BrowserCommandActionsKey.self] }
        set { self[BrowserCommandActionsKey.self] = newValue }
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browserCommandActions) private var actions

    var body: some Commands {
        CommandMenu("浏览器") {
            Button("聚焦地址栏") { actions?.focusAddress() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions == nil)
            Button("新建标签页") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions == nil)
            Button("关闭标签页") { actions?.closeTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(actions == nil)
            Button("恢复关闭的标签页") { actions?.reopenTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(actions?.canReopenTab != true)
            Divider()
            Button("下一个标签页") { actions?.nextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(actions == nil)
            Button("上一个标签页") { actions?.previousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(actions == nil)
            Divider()
            Button("重新载入") { actions?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions?.canReload != true)
            Button("在页面中查找") { actions?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions?.canFind != true)
        }
    }
}
