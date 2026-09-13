import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var bands: []
    required property string performanceMode
    property bool restartRequested: false

    readonly property int maximumBands: 64
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: root.configHome
        + "/hypr/scripts/quickshell_lockscreen_audio.sh"
    readonly property real silenceThreshold: 0.018

    function clampUnit(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 0;
        return Math.max(0, Math.min(1, numeric));
    }

    function threshold(value) {
        const bounded = clampUnit(value);
        return bounded < silenceThreshold ? 0 : bounded;
    }

    function zeroSpectrum() {
        const values = [];
        for (let i = 0; i < maximumBands; ++i)
            values.push(0);
        return values;
    }

    function parseFrame(data) {
        const frame = String(data || "").trim();
        const result = [];
        let start = 0;
        while (start <= frame.length && result.length < maximumBands) {
            const delimiter = frame.indexOf(";", start);
            const end = delimiter >= 0 ? delimiter : frame.length;
            if (end > start)
                result.push(threshold(Number(frame.slice(start, end)) / 1000));
            if (delimiter < 0)
                break;
            start = delimiter + 1;
        }
        if (result.length === 0)
            return;
        while (result.length < maximumBands)
            result.push(0);
        bands = result;
    }

    function startAnalyzer() {
        if (root.enabled && !audioProcess.running)
            audioProcess.running = true;
    }

    function restartAnalyzer() {
        if (!root.enabled)
            return;
        if (audioProcess.running) {
            restartRequested = true;
            audioProcess.running = false;
        } else {
            startAnalyzer();
        }
    }

    onPerformanceModeChanged: root.restartAnalyzer()

    onEnabledChanged: {
        if (enabled) {
            startAnalyzer();
        } else {
            restartRequested = false;
            if (audioProcess.running)
                audioProcess.running = false;
            bands = zeroSpectrum();
        }
    }

    Component.onCompleted: {
        bands = zeroSpectrum();
        root.startAnalyzer();
    }

    Process {
        id: audioProcess
        command: [root.helper, root.performanceMode]
        stdout: SplitParser {
            onRead: data => root.parseFrame(data)
        }
        onExited: {
            root.bands = root.zeroSpectrum();
            if (root.restartRequested && root.enabled) {
                root.restartRequested = false;
                root.startAnalyzer();
            }
        }
    }
}
