pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland

// Sway's get_tree is authoritative for applications on hidden workspaces.
// Foreign-toplevel screen lists only describe visible/current workspaces and
// previously made the bar omit Steam on workspace 4 when viewing workspace 2.
Singleton {
    id: root
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string workspaceScript: configHome
        + "/sway/awtarchy-trial/workspace-state.py"
    property var workspaces: ({ values: [] })
    property var toplevels: ({ values: [] })
    property var focusedMonitor: null
    property var activeToplevel: null
    property string workspaceFingerprint: ""
    property string focusToken: ""
    property string windowFingerprint: ""
    property string lastFocusName: ""
    property string lastWindowTitle: ""
    signal rawEvent(var event)

    function emitEvent(name, fields) {
        const values = fields || [];
        root.rawEvent({
            name: name,
            parse: function(count) { return values.slice(0, count); }
        });
    }

    function numericWorkspaces() {
        return (root.workspaces.values || [])
            .filter(w => Number.isInteger(w.id) && w.id >= 1 && w.id <= 10)
            .sort((a, b) => a.id - b.id);
    }

    function activateWorkspace(selector) {
        const key = String(selector || "");
        const all = numericWorkspaces();
        let number = null;
        if (key === "e-1" || key === "e+1") {
            const focused = all.findIndex(w => w.focused);
            if (focused < 0 || !all.length)
                return false;
            const step = key === "e-1" ? -1 : 1;
            number = all[(focused + step + all.length) % all.length].id;
        } else {
            number = Number(key);
        }
        if (!Number.isInteger(number) || number < 1 || number > 10)
            return false;
        I3.dispatch("workspace number " + number);
        return true;
    }

    function moveWorkspace(direction) {
        const choices = { u: "up", d: "down", l: "left", r: "right",
                          up: "up", down: "down", left: "left", right: "right" };
        const value = choices[String(direction)] || "";
        if (!value)
            return false;
        I3.dispatch("move workspace to output " + value);
        return true;
    }

    function toggleUtility(appId, command) {
        const values = typeof ToplevelManager === "undefined"
            ? [] : (ToplevelManager.toplevels.values || []);
        const found = values.filter(t => String(t.appId || "") === String(appId));
        if (found.length) {
            const current = found.find(t => t.activated);
            if (current)
                current.close();
            else
                found[0].activate();
            return true;
        }
        Quickshell.execDetached(command);
        return true;
    }

    function refreshMonitors() {
        // Show the focused native workspace even if the Sway JSON helper has
        // not started yet. Do not invent occupancy for hidden workspaces.
        if (!(root.workspaces.values || []).length) {
            const native = I3.workspaces.values || [];
            const fallback = native.map(w => ({
                id: Number(w.number),
                name: String(w.name || ""),
                monitor: { name: w.monitor ? String(w.monitor.name) : "" },
                active: Boolean(w.active),
                focused: Boolean(w.focused),
                urgent: Boolean(w.urgent),
                hasFullscreen: false,
                toplevels: { values: [] }
            })).filter(w => Number.isInteger(w.id)
                && w.id >= 1 && w.id <= 10 && w.monitor.name.length > 0);
            if (fallback.length)
                root.workspaces = { values: fallback };
        }
        if (!workspaceReader.running)
            workspaceReader.exec(["python3", root.workspaceScript]);
    }

    function applyWorkspaceState(state) {
        if (!Array.isArray(state))
            throw new Error("Expected array from Sway workspace helper");
        // Workspace state is authoritative through swaymsg get_tree. The
        // foreign-toplevel API is optional and must never blank the bar.
        const nativeWindows = typeof ToplevelManager === "undefined"
            ? [] : (ToplevelManager.toplevels.values || []);
        const mappedWorkspaces = [];
        const mappedWindows = [];

        for (const entry of state) {
            const id = Number(entry.id);
            const name = String(entry.name || "");
            const output = String(entry.monitor || "");
            if (!Number.isInteger(id) || id < 1 || id > 10)
                continue; // __i3_scratch and other special workspaces
            const clients = (entry.clients || []).map(client => {
                const title = String(client.title || "");
                const appId = String(client.app_id || "");
                const native = nativeWindows.find(t => String(t.title || "") === title
                    && String(t.appId || "") === appId) || null;
                return {
                    title: title,
                    activated: Boolean(client.focused),
                    urgent: Boolean(client.urgent),
                    monitor: { name: output },
                    workspace: { id: id, name: name },
                    wayland: native,
                    lastIpcObject: {
                        class: appId, initialClass: appId, title: title
                    }
                };
            });
            mappedWindows.push(...clients);
            mappedWorkspaces.push({
                id: id,
                name: name,
                monitor: { name: output },
                active: Boolean(entry.active),
                focused: Boolean(entry.focused),
                urgent: Boolean(entry.urgent),
                hasFullscreen: Boolean(entry.fullscreen),
                toplevels: { values: clients }
            });
        }

        // Sway always has at least one live numbered workspace in this
        // managed session. Ignore momentary blank/inconsistent IPC snapshots
        // instead of blanking both bars until the next successful poll.
        if (!mappedWorkspaces.length)
            return;

        const wsSignature = JSON.stringify(mappedWorkspaces.map(w =>
            [w.id, w.monitor.name, w.active, w.focused, w.urgent,
             w.toplevels.values.map(t => [t.title, t.lastIpcObject.class])]));
        if (root.workspaceFingerprint !== wsSignature) {
            root.workspaceFingerprint = wsSignature;
            root.workspaces = { values: mappedWorkspaces };
        }
        const windowSignature = JSON.stringify(mappedWindows.map(t =>
            [t.title, t.workspace.id, t.activated]));
        if (root.windowFingerprint !== windowSignature) {
            root.windowFingerprint = windowSignature;
            root.toplevels = { values: mappedWindows };
        }

        root.activeToplevel = mappedWindows.find(t => t.activated) || null;
        const focus = mappedWorkspaces.find(w => w.focused);
        const focusName = focus ? focus.monitor.name : root.lastFocusName;
        root.focusedMonitor = focusName ? { name: focusName } : null;
        if (root.lastFocusName !== focusName) {
            root.lastFocusName = focusName;
            emitEvent("focusedmon", [focusName]);
        }

        // A new window opening changes workspace occupancy but must NOT be
        // interpreted as a workspace switch: shell.qml closes flyouts on
        // "workspace" raw events. Only actual focus transitions emit it.
        const focusToken = focus ? focus.monitor.name + "|" + focus.id : "";
        if (root.focusToken !== focusToken) {
            root.focusToken = focusToken;
            emitEvent("workspace", []);
        }
        const activeTitle = root.activeToplevel ? root.activeToplevel.title : "";
        if (root.lastWindowTitle !== activeTitle) {
            root.lastWindowTitle = activeTitle;
            emitEvent("activewindow", [
                root.activeToplevel ? root.activeToplevel.lastIpcObject.class : "",
                activeTitle
            ]);
        }
    }

    Process {
        id: workspaceReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyWorkspaceState(JSON.parse(text));
                } catch (error) {
                    console.warn("SwayBridge: workspace state parse failed", error);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length)
                    console.warn("SwayBridge: workspace helper:", message);
            }
        }
    }

    Connections {
        target: I3
        function onRawEvent(event) { root.refreshMonitors(); }
    }
    Timer {
        interval: 700
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshMonitors()
    }
}
