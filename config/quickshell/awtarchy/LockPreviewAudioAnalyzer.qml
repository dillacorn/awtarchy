import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var bands: []
    property var targetBands: []

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

    function normalizedSpectrum(values) {
        const result = [];
        for (let i = 0; i < maximumBands; ++i) {
            const value = i < values.length ? values[i] : 0;
            result.push(threshold(value));
        }
        return result;
    }

    function parseFrame(data) {
        const fields = String(data || "").trim().split(";");
        const values = [];
        for (let i = 0; i < fields.length && values.length < maximumBands; ++i) {
            if (fields[i].length === 0)
                continue;
            values.push(clampUnit(Number(fields[i]) / 1000));
        }
        if (values.length === 0)
            return;
        targetBands = normalizedSpectrum(values);
        ensureSmoothing();
    }

    function smoothed(current, target) {
        const factor = target > current ? 0.42 : 0.16;
        const next = current + (target - current) * factor;
        return Math.abs(next - target) < 0.001 ? target : next;
    }

    function ensureSmoothing() {
        if (!smoothingTimer.running)
            smoothingTimer.start();
    }

    function clearTargets() {
        targetBands = zeroSpectrum();
    }

    function startAnalyzer() {
        if (root.enabled && !audioProcess.running)
            audioProcess.running = true;
    }

    function settled() {
        if (bands.length !== targetBands.length)
            return false;
        for (let i = 0; i < targetBands.length; ++i) {
            if (Math.abs(Number(bands[i] || 0) - Number(targetBands[i] || 0)) >= 0.001)
                return false;
        }
        return true;
    }

    onEnabledChanged: {
        if (enabled) {
            startAnalyzer();
        } else {
            if (audioProcess.running)
                audioProcess.running = false;
            clearTargets();
            ensureSmoothing();
        }
    }

    Component.onCompleted: {
        bands = zeroSpectrum();
        targetBands = zeroSpectrum();
        root.startAnalyzer();
    }

    Process {
        id: audioProcess
        command: [root.helper]
        stdout: SplitParser {
            onRead: data => root.parseFrame(data)
        }
        onExited: {
            root.clearTargets();
            root.ensureSmoothing();
        }
    }

    Timer {
        id: smoothingTimer
        interval: 33
        repeat: true
        running: false
        onTriggered: {
            const next = [];
            for (let i = 0; i < root.maximumBands; ++i) {
                const current = i < root.bands.length ? Number(root.bands[i]) : 0;
                const target = i < root.targetBands.length ? Number(root.targetBands[i]) : 0;
                next.push(root.smoothed(current, target));
            }
            root.bands = next;
            if (root.settled())
                stop();
        }
    }
}
