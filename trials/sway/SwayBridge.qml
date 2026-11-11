pragma Singleton
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
import Quickshell.WindowManager

// Sway's native I3 IPC is the workspace and monitor authority.
// Foreign-toplevel is used only for window information; never call hyprctl.
Singleton {
    id: root
    property var workspaces: ({ values: [] })
    property var toplevels: ({ values: [] })
    property var focusedMonitor: null
    property var activeToplevel: null
    property string lastFocusName: ""
    property string lastWindowTitle: ""
    property string workspaceFingerprint: ""
    property string windowFingerprint: ""
    signal rawEvent(var event)

    function emitEvent(name, fields) {
        const values = fields || [];
        root.rawEvent({
            name: name,
            parse: function(count) { return values.slice(0, count); }
        });
    }
    function numericWorkspaces() {
        return (I3.workspaces.values || []).filter(ws => {
            const n = Number(ws.number);
            return Number.isInteger(n) && n > 0 && n <= 10;
        }).sort((a, b) => a.number - b.number);
    }
    function activateWorkspace(selector) {
        const str = String(selector || "");
        const all = numericWorkspaces();
        let requested = null;
        if (str === "e-1" || str === "e+1") {
            const current = all.findIndex(w => w.focused);
            if (current < 0 || !all.length) return false;
            const change = str === "e-1" ? -1 : 1;
            requested = all[(current + change + all.length) % all.length].number;
        } else {
            requested = Number(str);
        }
        if (!Number.isInteger(requested) || requested < 1 || requested > 10)
            return false;
        I3.dispatch("workspace number " + requested);
        return true;
    }
    function moveWorkspace(dir) {
        const directions = { u: "up", d: "down", l: "left", r: "right",
                             up: "up", down: "down", left: "left", right: "right" };
        const command = directions[String(dir)] || "";
        if (!command) return false;
        I3.dispatch("move workspace to output " + command);
        return true;
    }
    function toggleUtility(appId, command) {
        const items = ToplevelManager.toplevels.values || [];
        const matched = items.filter(t => String(t.appId || "") === String(appId));
        if (matched.length > 0) {
            const current = matched.find(t => t.activated);
            if (current) current.close();
            else matched[0].activate();
            return true;
        }
        Quickshell.execDetached(command);
        return true;
    }
    function refreshMonitors() {
        const monitors = I3.monitors.values || [];
        const nativeWorkspaces = I3.workspaces.values || [];
        const windows = ToplevelManager.toplevels.values || [];
        const focusedName = I3.focusedMonitor
            ? String(I3.focusedMonitor.name) : "";
        const name = focusedName || root.lastFocusName
            || (monitors.length ? String(monitors[0].name) : "");

        const mapped = windows.map(w => {
            const onMonitor = w.screens && w.screens.length
                ? String(w.screens[0].name || "") : "";
            const workspace = nativeWorkspaces.find(ws =>
                ws.active && ws.monitor && String(ws.monitor.name) === onMonitor);
            return {
                title: String(w.title || ""),
                activated: Boolean(w.activated),
                urgent: false,
                monitor: { name: onMonitor },
                workspace: {
                    id: workspace ? Number(workspace.number) : -1,
                    name: workspace ? String(workspace.name) : ""
                },
                wayland: w,
                lastIpcObject: {
                    class: String(w.appId || ""),
                    initialClass: String(w.appId || ""),
                    title: String(w.title || "")
                }
            };
        });
        const mappedWorkspaces = nativeWorkspaces.map(ws => {
            const display = ws.monitor ? String(ws.monitor.name) : "";
            const members = mapped.filter(t =>
                t.monitor.name === display && t.workspace.name === String(ws.name));
            return {
                id: Number(ws.number),
                name: String(ws.name),
                monitor: { name: display },
                active: Boolean(ws.active),
                focused: Boolean(ws.focused),
                urgent: Boolean(ws.urgent),
                hasFullscreen: members.some(t => t.wayland && t.wayland.fullscreen),
                toplevels: { values: members },
                nativeWorkspace: ws
            };
        });
        const wsSig = JSON.stringify(mappedWorkspaces.map(ws =>
            [ws.id, ws.monitor.name, ws.active, ws.focused, ws.urgent, ws.toplevels.values.length]));
        const winSig = JSON.stringify(mapped.map(t =>
            [t.title, t.monitor.name, t.activated, t.workspace.id]));
        if (root.workspaceFingerprint !== wsSig) {
            root.workspaceFingerprint = wsSig;
            root.workspaces = { values: mappedWorkspaces };
            emitEvent("workspace", []);
        }
        if (root.windowFingerprint !== winSig) {
            root.windowFingerprint = winSig;
            root.toplevels = { values: mapped };
        }
        root.activeToplevel = mapped.find(t => t.activated) || null;
        root.focusedMonitor = name ? { name: name } : null;
        if (root.lastFocusName !== name) {
            root.lastFocusName = name;
            emitEvent("focusedmon", [name]);
        }
        const title = root.activeToplevel ? root.activeToplevel.title : "";
        if (root.lastWindowTitle !== title) {
            root.lastWindowTitle = title;
            emitEvent("activewindow", [root.activeToplevel
                ? root.activeToplevel.lastIpcObject.class : "", title]);
        }
    }
    Connections {
        target: I3
        function onRawEvent(event) { root.refreshMonitors(); }
    }
    Timer {
        interval: 650
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshMonitors()
    }
}
