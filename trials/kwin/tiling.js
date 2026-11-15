// Isolated Awtarchy KWin trial: conservative dwindle-style placement.
// This is NOT a production tiler and is not loaded outside the private KWin trial.
"use strict";

(function () {
    const OUTER = 9;
    const INNER = 6;
    const MIN_EDGE = 72;
    const FLOAT_CLASSES = new Set([
        "btop", "maccel", "smtty", "smtty-o", "wallpicker", "wiremix",
        "hyprmoncfg", "nwg-displays", "awtarchy-qalc", "awtarchy-tips-tui",
        "awtarchy-default-apps", "pavucontrol", "pulsemixer", "hypr_quicksettings"
    ]);
    const order = new Map();
    const floating = new Set();
    const originalGeometry = new Map();
    let nextOrder = 0;

    function identity(window) {
        if (!window) return "";
        return String(window.internalId || window.windowId || "");
    }

    function rank(window) {
        const key = identity(window);
        if (!key) return Number.MAX_SAFE_INTEGER;
        if (!order.has(key)) order.set(key, nextOrder++);
        return order.get(key);
    }

    function sameOutput(left, right) {
        return left === right || Boolean(left && right && left.name && left.name === right.name);
    }

    function sameDesktop(window, desktop) {
        const desktops = window.desktops || [];
        return desktops.some(item => item === desktop ||
            Boolean(item && desktop && item.id === desktop.id));
    }

    function eligible(window, output, desktop) {
        if (!window || !window.normalWindow || window.deleted ||
            window.minimized || window.fullScreen || window.onAllDesktops ||
            window.keepAbove || window.keepBelow || window.specialWindow ||
            floating.has(identity(window)) ||
            !sameOutput(window.output, output) || !sameDesktop(window, desktop)) {
            return false;
        }
        const klass = String(window.resourceClass || "").toLowerCase();
        if (FLOAT_CLASSES.has(klass) ||
            /^(steam_app_[0-9]+|gamescope)$/.test(klass)) {
            return false;
        }
        return true;
    }

    function rectangle(rect) {
        if (!rect) return null;
        const x = Math.round(Number(rect.x));
        const y = Math.round(Number(rect.y));
        const width = Math.round(Number(rect.width));
        const height = Math.round(Number(rect.height));
        return [x, y, width, height].every(Number.isFinite) &&
            width > 0 && height > 0 ? { x, y, width, height } : null;
    }

    function positions(area, amount) {
        const available = rectangle(area);
        if (!available || amount < 1) return [];
        const rects = [];
        const first = {
            x: available.x + OUTER,
            y: available.y + OUTER,
            width: available.width - 2 * OUTER,
            height: available.height - 2 * OUTER
        };
        if (first.width < MIN_EDGE || first.height < MIN_EDGE) return [];
        let remaining = first;
        for (let i = 0; i < amount; i++) {
            if (i === amount - 1) {
                rects.push(remaining);
                continue;
            }
            // Alternate: horizontal split first, then vertical, like a
            // simple dwindle tree; leave INNER pixels between neighboring tiles.
            const splitX = i % 2 === 0;
            const length = splitX ? remaining.width : remaining.height;
            const firstLength = Math.floor((length - INNER) / 2);
            const secondLength = length - INNER - firstLength;
            if (firstLength < MIN_EDGE || secondLength < MIN_EDGE) {
                return [];
            }
            const tile = { ...remaining };
            if (splitX) {
                tile.width = firstLength;
                remaining = {
                    ...remaining,
                    x: remaining.x + firstLength + INNER,
                    width: secondLength
                };
            } else {
                tile.height = firstLength;
                remaining = {
                    ...remaining,
                    y: remaining.y + firstLength + INNER,
                    height: secondLength
                };
            }
            rects.push(tile);
        }
        return rects;
    }

    let tiling = false;
    function arrange() {
        if (tiling) return;
        tiling = true;
        try {
            const screens = workspace.screens || [];
            const windows = workspace.stackingOrder || [];
            for (const output of screens) {
                const desktop = typeof workspace.currentDesktopForScreen === "function" ?
                    workspace.currentDesktopForScreen(output) : workspace.currentDesktop;
                if (!desktop) continue;
                const candidates = windows.filter(window => eligible(window, output, desktop));
                candidates.sort((a, b) => rank(a) - rank(b));
                const available = workspace.clientArea(KWin.MaximizeArea, output, desktop);
                const geometry = positions(available, candidates.length);
                if (geometry.length !== candidates.length) continue;
                for (let i = 0; i < candidates.length; i++) {
                    const window = candidates[i];
                    const target = geometry[i];
                    const current = rectangle(window.frameGeometry);
                    if (current && current.x === target.x && current.y === target.y &&
                        current.width === target.width && current.height === target.height) {
                        continue;
                    }
                    const id = identity(window);
                    if (id && !originalGeometry.has(id) && current) {
                        originalGeometry.set(id, current);
                    }
                    window.frameGeometry = target;
                }
            }
        } finally {
            tiling = false;
        }
    }

    function toggleFloating() {
        const window = workspace.activeWindow;
        if (!window || !window.normalWindow || window.fullScreen) return;
        const id = identity(window);
        if (!id) return;
        if (floating.has(id)) {
            floating.delete(id);
        } else {
            floating.add(id);
            const original = originalGeometry.get(id);
            if (original) window.frameGeometry = { ...original };
        }
        arrange();
    }

    registerShortcut("awtarchy-kwin-floating-meta",
        "Awtarchy: toggle window floating (Meta)", "Meta+F", toggleFloating);
    registerShortcut("awtarchy-kwin-floating-alt",
        "Awtarchy: toggle window floating (Alt)", "Alt+F", toggleFloating);

    function attach(window) {
        if (!window) return;
        rank(window);
        for (const name of [
            "fullScreenChanged", "minimizedChanged", "desktopsChanged", "outputChanged"
        ]) {
            const signal = window[name];
            if (signal && typeof signal.connect === "function") {
                signal.connect(arrange);
            }
        }
    }

    // KWin sends these events through its documented script QObject API.
    for (const window of workspace.stackingOrder || []) attach(window);
    workspace.windowAdded.connect(function (window) {
        attach(window);
        arrange();
    });
    workspace.windowRemoved.connect(function (window) {
        const key = identity(window);
        if (key) {
            order.delete(key);
            floating.delete(key);
            originalGeometry.delete(key);
        }
        arrange();
    });
    workspace.desktopsChanged.connect(arrange);
    workspace.screensChanged.connect(arrange);
    workspace.currentDesktopChanged.connect(arrange);
    arrange();
})();
