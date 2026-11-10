pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.WindowManager

// Jay uses ext-workspace-v1 and foreign-toplevel management. No Hyprland
// socket, mmsg, keyboard injection, or tag-to-workspace emulation.
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

    function monitorForWindow(toplevel) {
        if (!toplevel || !toplevel.screens || toplevel.screens.length === 0)
            return "";
        return String(toplevel.screens[0].name || "");
    }

    function monitorForWindowset(set) {
        if (!set || !set.projection || !set.projection.screens
                || set.projection.screens.length === 0)
            return "";
        return String(set.projection.screens[0].name || "");
    }

    function numericalWorkspaces() {
        return (WindowManager.windowsets || []).filter(w => {
            const value = Number(w.name);
            return Number.isInteger(value) && value > 0 && value <= 10;
        }).sort((a, b) => Number(a.name) - Number(b.name));
    }

    function findWorkspace(name) {
        return (WindowManager.windowsets || []).find(w => String(w.name) === String(name)) || null;
    }

    function activateWorkspace(selector) {
        const requested = String(selector || "");
        const workspaces = root.numericalWorkspaces();
        let workspace = null;
        if (requested === "e-1" || requested === "e+1") {
            const current = workspaces.findIndex(w => w.active
                && root.monitorForWindowset(w) === root.lastFocusName);
            const offset = requested === "e-1" ? -1 : 1;
            if (current < 0 || workspaces.length === 0)
                return false;
            workspace = workspaces[(current + offset + workspaces.length) % workspaces.length];
        } else {
            workspace = root.findWorkspace(requested);
        }
        // ext-workspace-v1 can activate existing workspaces. Creating a missing
        // one remains the compositor's native keyboard shortcut responsibility.
        if (!workspace || !workspace.canActivate)
            return false;
        workspace.activate();
        return true;
    }

    function moveWorkspace(direction) {
        // Shared bar uses compact u/d/l/r codes; Jay Wayland uses full names.
        const names = { u: "up", d: "down", l: "left", r: "right" };
        direction = names[String(direction)] || String(direction);
        const origin = root.focusedMonitor ? String(root.focusedMonitor.name) : "";
        const screens = Quickshell.screens || [];
        const current = screens.find(s => s && String(s.name) === origin);
        if (!current)
            return false;
        const candidates = screens.filter(s => {
            if (!s || s === current)
                return false;
            if (direction === "left") return s.x < current.x;
            if (direction === "right") return s.x > current.x;
            if (direction === "up") return s.y < current.y;
            if (direction === "down") return s.y > current.y;
            return false;
        }).sort((a, b) => {
            const dxA = a.x - current.x, dyA = a.y - current.y;
            const dxB = b.x - current.x, dyB = b.y - current.y;
            return dxA * dxA + dyA * dyA - dxB * dxB - dyB * dyB;
        });
        if (!candidates.length)
            return false;
        const workspace = (WindowManager.windowsets || []).find(w =>
            w.active && root.monitorForWindowset(w) === origin);
        if (!workspace || !workspace.canSetProjection)
            return false;
        const target = WindowManager.screenProjection(candidates[0]);
        if (!target)
            return false;
        workspace.setProjection(target);
        return true;
    }

    function refreshMonitors() {
        const nativeToplevels = ToplevelManager.toplevels.values || [];
        const active = ToplevelManager.activeToplevel;
        const activeMonitor = root.monitorForWindow(active);
        const displays = Quickshell.screens || [];
        const monitor = activeMonitor || root.lastFocusName
            || (displays.length > 0 ? String(displays[0].name) : "");
        const mapped = nativeToplevels.map(t => {
            const name = root.monitorForWindow(t);
            const w = (WindowManager.windowsets || []).find(ws =>
                ws.active && root.monitorForWindowset(ws) === name);
            const id = w ? Number(w.name) : -1;
            return {
                title: String(t.title || ""),
                activated: Boolean(t.activated),
                urgent: false,
                monitor: { name: name },
                workspace: { id: Number.isInteger(id) ? id : -1, name: w ? String(w.name) : "" },
                wayland: t,
                lastIpcObject: { class: String(t.appId || ""), initialClass: String(t.appId || ""), title: String(t.title || "") }
            };
        });
        const mappedWorkspaces = (WindowManager.windowsets || []).map(w => {
            const name = root.monitorForWindowset(w);
            const id = Number(w.name);
            const members = mapped.filter(t => t.monitor.name === name && t.workspace.name === String(w.name));
            return {
                id: Number.isInteger(id) ? id : -1,
                name: String(w.name),
                monitor: { name: name },
                active: Boolean(w.active),
                focused: Boolean(w.active && name === monitor),
                urgent: Boolean(w.urgent),
                hasFullscreen: members.some(t => t.wayland && t.wayland.fullscreen),
                toplevels: { values: members },
                nativeWindowset: w
            };
        });

        const wsSignature = JSON.stringify(mappedWorkspaces.map(w => [
            w.name, w.monitor.name, w.active, w.urgent, w.hasFullscreen, w.toplevels.values.length
        ]));
        const winSignature = JSON.stringify(mapped.map(w => [w.title, w.monitor.name, w.activated, w.workspace.id]));

        if (root.workspaceFingerprint !== wsSignature) {
            root.workspaceFingerprint = wsSignature;
            root.workspaces = { values: mappedWorkspaces };
            emitEvent("workspace", []);
        }
        if (root.windowFingerprint !== winSignature) {
            root.windowFingerprint = winSignature;
            root.toplevels = { values: mapped };
        }
        root.activeToplevel = mapped.find(t => t.activated) || null;
        root.focusedMonitor = monitor ? { name: monitor } : null;
        if (root.lastFocusName !== monitor) {
            root.lastFocusName = monitor;
            emitEvent("focusedmon", [monitor]);
        }
        const title = root.activeToplevel ? root.activeToplevel.title : "";
        if (root.lastWindowTitle !== title) {
            root.lastWindowTitle = title;
            emitEvent("activewindow", [root.activeToplevel
                ? String(root.activeToplevel.lastIpcObject.class) : "", title]);
        }
    }

    // Generic Wayland state is cheap to read. Refresh only on actual changes;
    // the timer detects missed protocol events without spawning a CLI process.
    Timer {
        interval: 650
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshMonitors()
    }
}
