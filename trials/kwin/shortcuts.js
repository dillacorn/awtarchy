// KWin 6.8+ Awtarchy experimental workspace and window control.
// This file is enabled only inside the isolated temporary trial package.
// Stock KWin is stacking: no auto-tiling or Sway-style workspace moves are claimed.
"use strict";

(function () {
    function activeOutput() {
        const window = workspace.activeWindow;
        return (window && window.output) || workspace.activeScreen;
    }

    function desktop(number) {
        const list = workspace.desktops;
        return list && list[number - 1] || null;
    }

    function setDesktop(target) {
        if (!target) return;
        const output = activeOutput();
        if (output && typeof workspace.setCurrentDesktopForScreen === "function") {
            workspace.setCurrentDesktopForScreen(target, output);
        } else {
            workspace.currentDesktop = target;
        }
    }

    function show(number) {
        setDesktop(desktop(number));
    }

    function changeRelative(offset) {
        const list = workspace.desktops;
        if (!list || list.length < 1) return;
        const output = activeOutput();
        const current = output &&
            typeof workspace.currentDesktopForScreen === "function" ?
            workspace.currentDesktopForScreen(output) : workspace.currentDesktop;
        let index = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i] === current || (current && list[i].id === current.id)) {
                index = i;
                break;
            }
        }
        if (index < 0) return;
        setDesktop(list[(index + offset + list.length) % list.length]);
    }

    function moveWindow(number) {
        const target = desktop(number);
        const window = workspace.activeWindow;
        if (!target || !window || !window.normalWindow) return;
        window.desktops = [target];
    }

    function bind(id, caption, key, callback) {
        const registered = registerShortcut("awtarchy-" + id, caption, key, callback);
        if (!registered && typeof print === "function") {
            print("Awtarchy KWin shortcut registration failed: " + key);
        }
    }

    function launch(action) {
        callDBus("org.awtarchy.KWinTrial1", "/org/awtarchy/KWinTrial1",
            "org.awtarchy.KWinTrial1", "Launch", action);
    }

    bind("terminal", "Awtarchy: open terminal", "Meta+Return",
        function () { launch("terminal"); });
    bind("launcher", "Awtarchy: open launcher", "Meta+D",
        function () { launch("launcher"); });
    bind("launcher-alt", "Awtarchy: open launcher (Alt)", "Alt+P",
        function () { launch("launcher"); });

    for (let number = 1; number <= 10; number++) {
        const key = number === 10 ? "0" : String(number);
        bind("workspace-show-" + number, "Awtarchy: show workspace " + number,
            "Meta+" + key, function () { show(number); });
        bind("workspace-move-" + number, "Awtarchy: move window to workspace " + number,
            "Meta+Shift+" + key, function () { moveWindow(number); });
    }

    bind("workspace-prev", "Awtarchy: previous workspace", "Meta+[",
        function () { changeRelative(-1); });
    bind("workspace-next", "Awtarchy: next workspace", "Meta+]",
        function () { changeRelative(1); });

    // Avoid taking Meta+Arrow until the conflicting stock KWin quick-tile
    // shortcuts have a verified isolated rebind procedure.
    const directions = [
        ["left", "H", "slotSwitchWindowLeft"],
        ["down", "J", "slotSwitchWindowDown"],
        ["up", "K", "slotSwitchWindowUp"],
        ["right", "L", "slotSwitchWindowRight"]
    ];
    for (const [direction, key, method] of directions) {
        bind("focus-" + direction, "Awtarchy: focus window " + direction,
            "Meta+" + key, function () {
                if (typeof workspace[method] === "function") workspace[method]();
            });
    }

    bind("window-close", "Awtarchy: close window", "Meta+Q",
        function () { workspace.slotWindowClose(); });
    bind("window-fullscreen", "Awtarchy: toggle fullscreen", "Meta+Ctrl+F",
        function () { workspace.slotWindowFullScreen(); });
})();
