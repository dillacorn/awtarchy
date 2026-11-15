// Offline KWin script API test for predictable per-output dwindle placement.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(path.join(root, "trials/kwin/tiling.js"), "utf8");

function signal() {
    const callbacks = [];
    return {
        connect(callback) { callbacks.push(callback); },
        emit(...args) { for (const callback of callbacks) callback(...args); }
    };
}
const d1 = { id: "1" }, d2 = { id: "2" };
const dp1 = { name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 };
const dp3 = { name: "DP-3", x: 1920, y: 0, width: 1600, height: 900 };
function window(id, output, desktop = d1, klass = "foot") {
    return {
        internalId: id, resourceClass: klass, output, desktops: [desktop],
        normalWindow: true, fullScreen: false, minimized: false,
        frameGeometry: { x: 0, y: 0, width: 100, height: 100 },
        fullScreenChanged: signal(), minimizedChanged: signal(),
        desktopsChanged: signal(), outputChanged: signal()
    };
}
const a = window("a", dp1);
const b = window("b", dp1);
const c = window("c", dp3);
const float = window("float", dp1, d1, "btop");
const game = window("game", dp1, d1, "steam_app_730");
const full = window("full", dp1);
full.fullScreen = true;
const initialFloat = { ...float.frameGeometry };
const initialGame = { ...game.frameGeometry };
const initialFull = { ...full.frameGeometry };
const workspace = {
    screens: [dp1, dp3],
    stackingOrder: [a, b, c, float, game, full],
    currentDesktop: d1,
    currentDesktopForScreen: () => d1,
    clientArea: (_, output) => ({
        x: output.x, y: output.y,
        width: output.width, height: output.height
    }),
    windowAdded: signal(), windowRemoved: signal(),
    desktopsChanged: signal(), screensChanged: signal(),
    currentDesktopChanged: signal()
};

vm.runInNewContext(source, { workspace, KWin: { MaximizeArea: 2 } }, {
    filename: "tiling.js"
});
assert.equal(a.frameGeometry.x, 9);
assert.equal(a.frameGeometry.y, 9);
assert.equal(a.frameGeometry.height, 1062);
assert.equal(a.frameGeometry.width + b.frameGeometry.width, 1896);
assert.equal(b.frameGeometry.x - (a.frameGeometry.x + a.frameGeometry.width), 6);
assert.equal(c.frameGeometry.x, 1929);
assert.equal(c.frameGeometry.y, 9);
assert.equal(c.frameGeometry.width, 1582);
assert.equal(c.frameGeometry.height, 882);
assert.deepEqual(float.frameGeometry, initialFloat);
assert.deepEqual(game.frameGeometry, initialGame);
assert.deepEqual(full.frameGeometry, initialFull);

// Third tile splits remaining output vertically; existing order remains stable.
const d = window("d", dp1);
workspace.stackingOrder.push(d);
workspace.windowAdded.emit(d);
assert.equal(a.frameGeometry.x, 9);
assert.equal(b.frameGeometry.x, a.frameGeometry.x + a.frameGeometry.width + 6);
assert.equal(d.frameGeometry.x, b.frameGeometry.x);
assert.equal(d.frameGeometry.y, b.frameGeometry.y + b.frameGeometry.height + 6);

// Fullscreen games stay untouched, other windows reflow around them.
b.fullScreen = true;
b.fullScreenChanged.emit();
assert.deepEqual([a.frameGeometry.x, d.frameGeometry.x], [9, 969]);
assert.equal(b.frameGeometry.x, 963);

// Per-output and desktop isolation.
workspace.stackingOrder.push(window("e", dp1, d2));
workspace.currentDesktopChanged.emit();
assert.equal(c.frameGeometry.x, 1929);
workspace.stackingOrder.splice(workspace.stackingOrder.indexOf(d), 1);
workspace.windowRemoved.emit(d);
assert.equal(a.frameGeometry.width, 1902);

// Too many tiles for a small output: no negative/overlapping geometry.
const tiny = { name: "tiny", x: 0, y: 0, width: 100, height: 100 };
const z1 = window("z1", tiny), z2 = window("z2", tiny);
workspace.screens = [tiny];
workspace.stackingOrder = [z1, z2];
workspace.screensChanged.emit();
assert.equal(z1.frameGeometry.width, 100);
assert.equal(z2.frameGeometry.width, 100);
console.log("PASS: KWin trial tiling, exclusions, gaps, independent outputs, and reflow");
