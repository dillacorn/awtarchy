// Offline KWin 6 scripting API stub: no real KWin, display, or D-Bus required.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(path.join(root, "trials/kwin/shortcuts.js"), "utf8");
const desktops = Array.from({ length: 10 }, (_, n) => ({ id: String(n + 1) }));
const output = { name: "DP-1" };
const window = { output, normalWindow: true, desktops: [desktops[0]] };
const changes = [];
const actions = [];
const dbusCalls = [];
const shortcuts = new Map();
const workspace = {
    activeWindow: window, activeScreen: output, desktops,
    currentDesktop: desktops[0],
    currentDesktopForScreen(screen) {
        assert.equal(screen, output);
        return this.currentDesktop;
    },
    setCurrentDesktopForScreen(desktop, screen) {
        changes.push([desktop, screen]);
        this.currentDesktop = desktop;
    },
    slotSwitchWindowLeft() { actions.push("focus-left"); },
    slotSwitchWindowDown() { actions.push("focus-down"); },
    slotSwitchWindowUp() { actions.push("focus-up"); },
    slotSwitchWindowRight() { actions.push("focus-right"); },
    slotWindowClose() { actions.push("close"); },
    slotWindowFullScreen() { actions.push("fullscreen"); }
};
vm.runInNewContext(source, {
    workspace,
    callDBus(...args) { dbusCalls.push(args); },
    registerShortcut(id, title, keys, callback) {
        assert.equal(shortcuts.has(id), false);
        assert.equal([...shortcuts.values()].some(s => s.keys === keys), false);
        shortcuts.set(id, { title, keys, callback });
        return true;
    }
}, { filename: "shortcuts.js" });
assert.equal(shortcuts.size, 31);
assert.equal(shortcuts.get("awtarchy-workspace-show-10").keys, "Meta+0");
assert.equal(shortcuts.get("awtarchy-workspace-move-10").keys, "Meta+Shift+0");

shortcuts.get("awtarchy-workspace-show-3").callback();
assert.equal(changes.length, 1);
assert.equal(changes[0][0], desktops[2]);
assert.equal(changes[0][1], output);
shortcuts.get("awtarchy-workspace-move-2").callback();
assert.equal(window.desktops[0], desktops[1]);

shortcuts.get("awtarchy-workspace-next").callback();
assert.equal(changes.at(-1)[0], desktops[3]);
shortcuts.get("awtarchy-workspace-prev").callback();
assert.equal(changes.at(-1)[0], desktops[2]);
workspace.currentDesktop = desktops[9];
shortcuts.get("awtarchy-workspace-next").callback();
assert.equal(changes.at(-1)[0], desktops[0]);

workspace.desktops = [desktops[0]];
shortcuts.get("awtarchy-workspace-show-5").callback();
shortcuts.get("awtarchy-workspace-move-5").callback();
assert.equal(changes.at(-1)[0], desktops[0]);
assert.equal(window.desktops[0], desktops[1]);
workspace.desktops = desktops;
window.normalWindow = false;
shortcuts.get("awtarchy-workspace-move-3").callback();
assert.equal(window.desktops[0], desktops[1]);

shortcuts.get("awtarchy-focus-left").callback();
shortcuts.get("awtarchy-focus-down").callback();
shortcuts.get("awtarchy-focus-up").callback();
shortcuts.get("awtarchy-focus-right").callback();
shortcuts.get("awtarchy-window-close").callback();
shortcuts.get("awtarchy-window-fullscreen").callback();
assert.deepEqual(actions, [
    "focus-left", "focus-down", "focus-up", "focus-right", "close", "fullscreen"
]);
shortcuts.get("awtarchy-terminal").callback();
shortcuts.get("awtarchy-launcher").callback();
shortcuts.get("awtarchy-launcher-alt").callback();
assert.deepEqual(dbusCalls.map(call => call.at(-1)), [
    "terminal", "launcher", "launcher"
]);
console.log("PASS: KWin workspace and window shortcut API stub");
