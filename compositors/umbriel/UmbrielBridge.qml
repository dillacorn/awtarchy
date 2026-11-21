pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Umbriel's native workspace/window IPC reports both visible and hidden
// workspaces. Foreign-toplevel data is an optional Wayland integration.
Singleton {
    id: root
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string eventsScript: configHome
        + "/umbriel/awtarchy/workspace-events.py"
    property bool eventsEnabled: true
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
        // A global number identifies one named workspace across all outputs.
        // Output-local index is deliberately never used for navigation.
        return (root.workspaces.values || [])
            .filter(w => w.named && Number.isInteger(w.id) && w.id >= 1 && w.id <= 10)
            .sort((a, b) => a.id - b.id);
    }

    function activateWorkspace(selector, output) {
        const key = String(selector || "");
        const all = numericWorkspaces();
        let number = null;
        if (key === "e-1" || key === "e+1") {
            const activeHere = all.findIndex(w => w.active && w.monitor
                && w.monitor.name === output);
            const focused = activeHere >= 0 ? activeHere
                : all.findIndex(w => w.focused);
            if (focused < 0 || !all.length)
                return false;
            const step = key === "e-1" ? -1 : 1;
            number = all[(focused + step + all.length) % all.length].id;
        } else {
            number = Number(key);
            // Reject an outdated click on a bar from which the named workspace
            // was already transferred, rather than selecting another display.
            const target = all.find(w => w.id === number);
            if (output && (!target || !target.monitor || target.monitor.name !== output))
                return false;
        }
        if (!Number.isInteger(number) || number < 1 || number > 10)
            return false;
        if (all.filter(w => w.id === number).length !== 1)
            return false;
        // --name forces global lookup for digit-only names. Bare "1" means
        // the local position 1 on Umbriel's pointer-preferred output.
        Quickshell.execDetached([
            "umbriel", "msg", "workspace-switch", "--name", String(number)
        ]);
        return true;
    }

    function moveWorkspace(direction) {
        const choices = { u: "up", d: "down", l: "left", r: "right",
                          up: "up", down: "down", left: "left", right: "right" };
        const value = choices[String(direction)] || "";
        if (!value)
            return false;
        // Upstream provides explicit directional workspace moves.
        Quickshell.execDetached(["umbriel", "msg", "workspace-move-to-output-" + value]);
        return true;
    }

    function toggleUtility(appId, command) {
        // Route both the bar and the quick settings selector through the same
        // compositor-owned exact-window toggle as the keyboard shortcuts.
        const name = appId === "Wiremix" ? "wiremix"
            : appId === "awtarchy-default-apps" ? "default-apps" : "";
        if (!name)
            return false;
        Quickshell.execDetached([
            "python3", root.configHome + "/umbriel/awtarchy/toggle-utility.py",
            name
        ]);
        return true;
    }

    function applyWorkspaceState(state) {
        if (!Array.isArray(state))
            throw new Error("Expected array from Umbriel workspace helper");
        // Workspace state is authoritative through Umbriel's workspaces/windows IPC. The
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
                named: Boolean(entry.named),
                monitor: { name: output },
                active: Boolean(entry.active),
                focused: Boolean(entry.focused),
                urgent: Boolean(entry.urgent),
                hasFullscreen: Boolean(entry.fullscreen),
                toplevels: { values: clients }
            });
        }

        // Umbriel always has at least one live numbered workspace in this
        // managed session. Ignore momentary blank/inconsistent IPC snapshots
        // instead of blanking both bars until the next successful poll.
        if (!mappedWorkspaces.length)
            return;

        const wsSignature = JSON.stringify(mappedWorkspaces.map(w =>
            [w.id, w.monitor.name, w.named, w.active, w.focused, w.urgent,
             w.toplevels.values.map(t => [t.title, t.lastIpcObject.class])]));
        if (root.workspaceFingerprint !== wsSignature) {
            root.workspaceFingerprint = wsSignature;
            root.workspaces = { values: mappedWorkspaces };
        }
        const windowSignature = JSON.stringify(mappedWindows.map(t =>
            [t.title, t.lastIpcObject.class, t.workspace.id, t.activated]));
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

    // Umbriel sends full snapshots on change. The persistent subscriber also
    // removes duplicate window-coordinate updates before QML model rebuilding.
    // A failed connection is retried with backoff, never a 700 ms process loop.
    Process {
        id: workspaceSubscriber
        running: root.eventsEnabled
        command: ["python3", root.eventsScript]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.applyWorkspaceState(JSON.parse(line));
                } catch (error) {
                    console.warn("UmbrielBridge: invalid workspace event", error);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim().length)
                    console.warn("UmbrielBridge: workspace subscription:", line.trim());
            }
        }
        onExited: {
            root.eventsEnabled = false;
            subscriptionRetry.restart();
        }
    }

    Timer {
        id: subscriptionRetry
        interval: 2500
        repeat: false
        onTriggered: root.eventsEnabled = true
    }
}
