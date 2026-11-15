// KWin-native per-output workspace state publisher for a private trial.
// No timers, global configuration, shortcuts or compositor changes.
"use strict";

(function () {
    const service = "org.awtarchy.KWinTrial1";
    const path = "/org/awtarchy/KWinTrial1";
    const iface = "org.awtarchy.KWinTrial1";

    function sameOutput(a, b) {
        return a === b || Boolean(a && b && a.name && a.name === b.name);
    }

    function state() {
        const desktops = (workspace.desktops || []).map(function (d, i) {
            return { id: String(d.id), name: String(d.name || (i + 1)) };
        });
        const known = new Set(desktops.map(d => d.id));
        const outputs = (workspace.screens || []).map(function (screen) {
            const current = typeof workspace.currentDesktopForScreen === "function" ?
                workspace.currentDesktopForScreen(screen) : workspace.currentDesktop;
            const active = current && known.has(String(current.id)) ?
                String(current.id) : null;
            const used = new Set();
            for (const window of workspace.stackingOrder || []) {
                if (!window || !window.normalWindow || window.deleted ||
                    window.minimized || window.specialWindow ||
                    !sameOutput(window.output, screen)) {
                    continue;
                }
                if (window.onAllDesktops) {
                    for (const desktop of desktops) used.add(desktop.id);
                } else {
                    for (const desktop of window.desktops || []) {
                        const id = String(desktop.id);
                        if (known.has(id)) used.add(id);
                    }
                }
            }
            return {
                name: String(screen.name || ""),
                active,
                occupied: Array.from(used)
            };
        });
        return { version: 1, desktops, outputs };
    }

    let previous = "";
    function update() {
        const encoded = JSON.stringify(state());
        if (encoded === previous) return;
        previous = encoded;
        callDBus(service, path, iface, "UpdateState", encoded);
    }

    for (const name of [
        "windowAdded", "windowRemoved", "windowActivated",
        "currentDesktopChanged", "desktopsChanged", "screensChanged"
    ]) {
        const signal = workspace[name];
        if (signal && typeof signal.connect === "function") {
            signal.connect(update);
        }
    }
    update();
})();
