// KWin 6.8+ Awtarchy numbered workspace proof of concept.
// Session-specific script; do not auto-load into an existing Plasma session.
// Creates no desktops and changes no configuration files.
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

    function show(number) {
        const target = desktop(number);
        if (!target) return;
        const output = activeOutput();
        if (output && typeof workspace.setCurrentDesktopForScreen === "function") {
            workspace.setCurrentDesktopForScreen(target, output);
        } else {
            workspace.currentDesktop = target;
        }
    }

    function moveWindow(number) {
        const target = desktop(number);
        const window = workspace.activeWindow;
        if (!target || !window || !window.normalWindow) return;
        window.desktops = [target];
    }

    for (let number = 1; number <= 10; number++) {
        const key = number === 10 ? "0" : String(number);
        registerShortcut("awtarchy-workspace-show-" + number,
            "Awtarchy: show workspace " + number, "Meta+" + key,
            function () { show(number); });
        registerShortcut("awtarchy-workspace-move-" + number,
            "Awtarchy: move window to workspace " + number,
            "Meta+Shift+" + key, function () { moveWindow(number); });
    }
})();
