pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string weatherHelper:
        configHome + "/hypr/scripts/quickshell_lockscreen_weather.sh"
    readonly property int minimumRefreshIntervalMs: 1200000
    readonly property string configuredLocation:
        String(BarState.lockscreenWeatherLocation() || "").trim()
    readonly property bool refreshEnabled: BarState.lockscreenShowWeather()
    readonly property string configuredUnits: BarState.lockscreenWeatherUnits()

    property string lastRequestIdentity: ""
    property double lastRequestMs: 0

    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        const units = String(root.configuredUnits || "auto");
        if (!root.refreshEnabled || refreshProcess.running)
            return;

        const now = Date.now();
        const requestIdentity = location + "|" + units;
        const requestChanged = requestIdentity !== root.lastRequestIdentity;
        if (!requestChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestIdentity = requestIdentity;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh", location, units]);
    }

    Process {
        id: refreshProcess
    }

    Timer {
        interval: 1200000
        repeat: true
        running: root.refreshEnabled
        onTriggered: root.requestRefresh()
    }

    Timer {
        id: stateRefresh
        interval: 180
        repeat: false
        onTriggered: root.requestRefresh()
    }

    Connections {
        target: BarState
        function onRevisionChanged() {
            if (root.refreshEnabled)
                stateRefresh.restart();
        }
    }

    Component.onCompleted: {
        if (root.refreshEnabled)
            stateRefresh.restart();
    }
}
