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
    readonly property var configuredUnitModes: requiredUnitModes()
    readonly property bool refreshEnabled: configuredUnitModes.length > 0

    property string lastRequestIdentity: ""
    property double lastRequestMs: 0

    function normalizedUnitMode(value) {
        const mode = String(value || "auto");
        return ["auto", "fahrenheit", "celsius"].indexOf(mode) >= 0 ? mode : "auto";
    }

    function requiredUnitModes() {
        const modes = [];
        const seen = ({});
        function addProfile(profile) {
            if (!profile || typeof profile !== "object")
                return;
            if (profile.lockscreen_show_weather === true) {
                const mode = root.normalizedUnitMode(profile.lockscreen_weather_units);
                if (seen[mode])
                    return;
                seen[mode] = true;
                modes.push(mode);
            }
        }

        addProfile(BarState.lockscreenLastEditedProfile());
        const profiles = BarState.lockscreenMonitorProfiles();
        for (const name of Object.keys(profiles || ({})))
            addProfile(profiles[name]);
        return modes;
    }

    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        const modes = root.requiredUnitModes();
        if (modes.length === 0 || refreshProcess.running)
            return;

        const sortedModes = modes.slice().sort();
        const now = Date.now();
        const requestIdentity = location + "|" + sortedModes.join(",");
        const requestChanged = requestIdentity !== root.lastRequestIdentity;
        if (!requestChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestIdentity = requestIdentity;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh-set", location, JSON.stringify(modes)]);
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
