from pathlib import Path


def one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


path = Path('config/quickshell/awtarchy/QuickSettings.qml')
s = path.read_text()

s = one(s,
'''    property bool cursorSectionExpanded: false
    property bool lockscreenSectionExpanded: false''',
'''    property bool cursorSectionExpanded: false
    property bool lockscreenSectionExpanded: false
    readonly property bool cursorSectionOpen: cursorSectionExpanded
    readonly property bool lockscreenSectionOpen: lockscreenSectionExpanded''',
'quick settings section state aliases')

s = one(s,
'''    readonly property int panelFadeDuration: 140
    property var flyoutScreen: null''',
'''    readonly property int panelFadeDuration: 140
    readonly property int sectionActionColumnWidth: Math.max(132, scaledText(9) * 13)
    property var flyoutScreen: null''',
'shared action-column width')

old_cursor = '''                                    SettingsButton {
                                        label: root.cursorSectionExpanded ? "Collapse" : "Expand"
                                        active: root.cursorSectionExpanded
                                        textSize: root.scaledText(9)
                                        onClicked: root.cursorSectionExpanded = !root.cursorSectionExpanded
                                    }'''
new_cursor = '''                                    ColumnLayout {
                                        id: cursorSectionActions
                                        Layout.preferredWidth: root.sectionActionColumnWidth
                                        Layout.alignment: Qt.AlignRight
                                        spacing: 5
                                        SettingsButton {
                                            Layout.fillWidth: true
                                            label: root.cursorSectionOpen ? "Collapse Cursor" : "Expand Cursor"
                                            active: root.cursorSectionOpen
                                            textSize: root.scaledText(9)
                                            onClicked: root.cursorSectionExpanded = !root.cursorSectionExpanded
                                        }
                                    }'''
s = one(s, old_cursor, new_cursor, 'cursor action column')

s = one(s,
'''                                    ColumnLayout {
                                        id: lockscreenHeaderActions
                                        spacing: 5
                                        Layout.alignment: Qt.AlignTop
                                        SettingsButton {
                                            label: root.lockscreenSectionExpanded ? "Collapse" : "Expand"
                                            active: root.lockscreenSectionExpanded
                                            textSize: root.scaledText(9)
                                            onClicked: root.lockscreenSectionExpanded = !root.lockscreenSectionExpanded
                                        }
                                        SettingsButton {
                                            label: "Edit Layout"
                                            active: true
                                            textSize: root.scaledText(9)
                                            onClicked: root.openLockscreenEditor()
                                        }
                                    }''',
'''                                    ColumnLayout {
                                        id: lockscreenSectionActions
                                        Layout.preferredWidth: root.sectionActionColumnWidth
                                        Layout.alignment: Qt.AlignRight
                                        spacing: 5
                                        SettingsButton {
                                            Layout.fillWidth: true
                                            label: root.lockscreenSectionOpen ? "Collapse Lockscreen" : "Expand Lockscreen"
                                            active: root.lockscreenSectionOpen
                                            textSize: root.scaledText(9)
                                            onClicked: root.lockscreenSectionExpanded = !root.lockscreenSectionExpanded
                                        }
                                        SettingsButton {
                                            Layout.fillWidth: true
                                            label: "Edit Layout"
                                            active: true
                                            textSize: root.scaledText(9)
                                            onClicked: root.openLockscreenEditor()
                                        }
                                    }''',
'lockscreen action column')

iris = '''                                            SettingsButton { label: "Reverse Iris"; active: BarState.lockscreenEntryTransition() === "iris"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "iris"]) }
'''
s = one(s, iris, '', 'retired Iris quick setting')

path.write_text(s)
