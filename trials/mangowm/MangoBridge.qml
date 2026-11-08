pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Recreates only the Hyprland QML properties used by Awtarchy's shell,
// using Mango's documented 0.18.5 IPC without another compositor's tooling.
Singleton {
    id: root

    property var workspaces: ({ values: [] })
    property var toplevels: ({ values: [] })
    property var focusedMonitor: null
    property var activeToplevel: null
    property string focusName: ""
    property string activeWindowTitle: ""
    property string tagFingerprint: ""
    signal rawEvent(var event)

    readonly property string snapshotScript:
        (Quickshell.env("XDG_CONFIG_HOME") ||
            (Quickshell.env("HOME") + "/.config")) + "/mango/scripts/snapshot.py"

    function emitEvent(name, fields) {
        const payload = fields || [];
        root.rawEvent({
            name: name,
            parse: function(count) { return payload.slice(0, count); }
        });
    }

    function reconcile(snapshot) {
        const monitors = snapshot.monitors || [];
        const clients = snapshot.clients || [];
        if (!Array.isArray(monitors) || !Array.isArray(clients))
            return;

        let selected = monitors.find(mon => mon.active === true);
        if (!selected)
            selected = monitors[0] || null;
        const focusedName = selected ? String(selected.name || "") : "";
        const wmToplevels = ToplevelManager.toplevels.values;
        const nativeMatches = new Set();
        const mappedClients = clients.map(client => {
            const monitor = {name: String(client.monitor || "")};
            const tags = Array.isArray(client.tags) ? client.tags : [];
            const id = tags.length ? Number(tags[0]) : -1;
            let wayland = null;
            for (let i = 0; i < wmToplevels.length; ++i) {
                const t = wmToplevels[i];
                if (!t || nativeMatches.has(i))
                    continue;
                if (String(t.appId || "") === String(client.appid || "")
                        && String(t.title || "") === String(client.title || "")) {
                    wayland = t;
                    nativeMatches.add(i);
                    break;
                }
            }
            const workspace = {id: id, name: String(id), monitor: monitor};
            return {
                id: client.id,
                title: String(client.title || ""),
                urgent: Boolean(client.is_urgent),
                activated: Boolean(client.is_focused),
                monitor: monitor,
                workspace: workspace,
                wayland: wayland,
                lastIpcObject: {class: String(client.appid || ""),
                    initialClass: String(client.appid || ""), title: String(client.title || "")}
            };
        });

        const mappedTags = [];
        for (const monitor of monitors) {
            const mons = {name: String(monitor.name || "")};
            for (const tag of (monitor.tags || [])) {
                const id = Number(tag.index || 0);
                if (id <= 0)
                    continue;
                const members = mappedClients.filter(c =>
                    c.monitor.name === mons.name && clients.some(orig =>
                        orig.id === c.id && Array.isArray(orig.tags) && orig.tags.indexOf(id) >= 0));
                const active = Boolean(tag.is_active);
                mappedTags.push({
                    id: id, name: String(id), monitor: mons,
                    active: active, focused: active && monitor.active === true,
                    urgent: Boolean(tag.is_urgent),
                    hasFullscreen: members.some(c => clients.some(orig =>
                        orig.id === c.id && orig.is_fullscreen === true)),
                    toplevels: {values: members}
                });
            }
        }

        root.workspaces = {values: mappedTags};
        root.toplevels = {values: mappedClients};
        root.focusedMonitor = selected ? {name: focusedName} : null;
        const focusedWindow = mappedClients.find(c => c.activated);
        root.activeToplevel = focusedWindow || null;
        if (root.focusName !== focusedName) {
            root.focusName = focusedName;
            emitEvent("focusedmon", [focusedName]);
        }
        const title = focusedWindow ? String(focusedWindow.title) : "";
        if (root.activeWindowTitle !== title) {
            root.activeWindowTitle = title;
            emitEvent("activewindow", [focusedWindow
                ? String(focusedWindow.lastIpcObject.class) : "", title]);
        }
        // Send workspace changes only when the active tagset changes. A
        // periodic event would close every open Awtarchy floating flyout.
        const signature = JSON.stringify(monitors.map(mon => ({
            name: mon.name,
            active: mon.active,
            active_tags: mon.active_tags
        })));
        if (root.tagFingerprint !== signature) {
            root.tagFingerprint = signature;
            emitEvent("workspace", []);
        }
    }

    function refreshMonitors() {
        if (!snapshotProcess.running)
            snapshotProcess.exec(["python3", root.snapshotScript]);
    }

    property Process snapshotProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.reconcile(JSON.parse(text));
                } catch (error) {
                    console.warn("MangoBridge: invalid IPC snapshot:", error);
                }
            }
        }
    }

    property Timer refreshTimer: Timer {
        interval: 750
        repeat: true
        running: true
        onTriggered: root.refreshMonitors()
    }

    Component.onCompleted: refreshMonitors()
}
