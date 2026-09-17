pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string helper:
        configHome + "/hypr/scripts/quickshell_lockscreen_contrast.sh"
    readonly property string cachePath:
        cacheHome + "/awtarchy/lockscreen-contrast.json"
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var monitorAccents: ({})

    property var accents: ({
        logo: "#ffffff",
        time: "#ffffff",
        date: "#ffffff",
        username: "#ffffff",
        weather: "#ffffff",
        password: "#ffffff"
    })

    function normalizedColors(value) {
        const next = ({});
        const source = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
        for (const name of elementNames) {
            const color = String(source[name] || "").toLowerCase();
            next[name] = /^#[0-9a-f]{6}$/.test(color) ? color : "#ffffff";
        }
        return next;
    }

    function colorFor(name) {
        const value = String(accents && accents[name] !== undefined ? accents[name] : "#ffffff");
        return /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
    }

    function colorsForMonitor(name) {
        const key = String(name || "");
        const value = monitorAccents && monitorAccents[key];
        return value && typeof value === "object" && !Array.isArray(value)
            ? normalizedColors(value) : normalizedColors(accents);
    }

    function refreshAccent() {
        const text = String(contrastFile.text() || "").trim();
        if (text.length === 0)
            return;
        try {
            const parsed = JSON.parse(text);
            if (!parsed || parsed.provider !== "awtarchy-local-contrast"
                    || !parsed.colors || typeof parsed.colors !== "object")
                return;
            accents = normalizedColors(parsed.colors);
            const nextMonitors = ({});
            if (parsed.monitor_colors && typeof parsed.monitor_colors === "object"
                    && !Array.isArray(parsed.monitor_colors)) {
                for (const name of Object.keys(parsed.monitor_colors))
                    nextMonitors[name] = normalizedColors(parsed.monitor_colors[name]);
            }
            monitorAccents = nextMonitors;
        } catch (error) {
            // Keep existing safe contrast values if the local cache is malformed.
        }
    }

    function requestRefresh() {
        if (refreshProcess.running)
            return;
        refreshProcess.exec([root.helper]);
    }

    Process {
        id: refreshProcess
        onExited: root.refreshAccent()
    }

    FileView {
        id: contrastFile
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refreshAccent()
        onFileChanged: root.refreshAccent()
    }

    Timer {
        id: refreshDelay
        interval: 160
        repeat: false
        onTriggered: root.requestRefresh()
    }

    Connections {
        target: BarState
        function onRevisionChanged() {
            refreshDelay.restart();
        }
    }

    Component.onCompleted: refreshDelay.restart()
}
