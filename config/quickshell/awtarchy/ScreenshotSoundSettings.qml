import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Shared login and screenshot sound preferences for Sway and Hyprland.
// Screenshot playback confirms a captured image, never a Satty save event.
ColumnLayout {
    id: root

    property int textSize: 10
    property bool expanded: false
    property bool loaded: false
    property string message: ""
    property var values: ({ enabled: true, login: true, direct: true, satty: true, print: true })
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property bool isSway: String(Quickshell.env("XDG_CURRENT_DESKTOP") || "")
        .toLowerCase() === "sway"
    readonly property string helper: configHome
        + (isSway ? "/sway/awtarchy-trial/screenshot_sound.sh"
                  : "/hypr/scripts/screenshot_sound.sh")

    Layout.fillWidth: true
    spacing: 5

    function refresh() {
        if (reader.running || writer.running)
            return;
        reader.exec(["bash", helper, "get"]);
    }

    function change(key) {
        if (!loaded || reader.running || writer.running)
            return;
        const next = !Boolean(values[key]);
        message = "";
        writer.exec(["bash", helper, "set", key, next ? "true" : "false"]);
    }

    Component.onCompleted: refresh()

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    for (const key of ["enabled", "login", "direct", "satty", "print"]) {
                        if (typeof parsed[key] !== "boolean")
                            throw new Error("invalid screenshot sound state");
                    }
                    root.values = parsed;
                    root.loaded = true;
                    root.message = "";
                } catch (error) {
                    root.loaded = false;
                    root.message = "Screenshot sound preferences unavailable";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loaded = false;
                root.message = "Screenshot sound preferences unavailable";
            }
        }
    }

    Process {
        id: writer
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.message = "Unable to save screenshot sound preferences";
            // Re-read actual persisted state instead of assuming the write succeeded.
            Qt.callLater(() => root.refresh());
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: "Login sound"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.textSize
        }

        SettingsButton {
            label: !root.loaded ? "Unavailable" : (root.values.login ? "On" : "Off")
            active: root.loaded && root.values.login
            available: root.loaded && !reader.running && !writer.running
            textSize: root.textSize
            onClicked: root.change("login")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: "Screenshot sounds"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.textSize
        }

        SettingsButton {
            label: root.expanded ? "Fewer options" : "Options"
            active: root.expanded
            textSize: root.textSize
            onClicked: root.expanded = !root.expanded
        }

        SettingsButton {
            label: !root.loaded ? "Unavailable" : (root.values.enabled ? "On" : "Off")
            active: root.loaded && root.values.enabled
            available: root.loaded && !reader.running && !writer.running
            textSize: root.textSize
            onClicked: root.change("enabled")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.expanded
        spacing: 5

        Text {
            Layout.fillWidth: true
            text: "Choose which screenshot shortcuts play the shutter click."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.textSize
            wrapMode: Text.Wrap
        }

        Repeater {
            model: [
                { key: "direct", label: "Focused display (Super+Shift+D)" },
                { key: "satty", label: "Satty captures (area, window, display)" },
                { key: "print", label: "Print Screen (Sway)" }
            ]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.textSize
                    wrapMode: Text.Wrap
                }

                SettingsButton {
                    label: !root.loaded ? "Unavailable"
                        : (root.values[modelData.key] ? "On" : "Off")
                    active: root.loaded && Boolean(root.values[modelData.key])
                    available: root.loaded && !reader.running && !writer.running
                    textSize: root.textSize
                    onClicked: root.change(modelData.key)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Screenshot master switch mutes all capture sounds; login audio is controlled separately."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.textSize
            wrapMode: Text.Wrap
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.message.length > 0
        text: root.message
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize
        wrapMode: Text.Wrap
    }
}
