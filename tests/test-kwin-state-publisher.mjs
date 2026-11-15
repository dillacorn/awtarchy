// KWin state publisher uses actual output and window data; no polling.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const source = fs.readFileSync(path.resolve(
    path.dirname(fileURLToPath(import.meta.url)), "../trials/kwin/state-publisher.js"
), "utf8");
function signal() {
    const callbacks = [];
    return {
        connect(fn) { callbacks.push(fn); },
        emit(...args) { callbacks.forEach(fn => fn(...args)); }
    };
}
const dp1 = { name: "DP-1" }, dp3 = { name: "DP-3" };
const desktops = [1, 2, 3].map(i => ({ id: String(i), name: String(i) }));
const a = { normalWindow: true, output: dp1, desktops: [desktops[1]] };
const b = { normalWindow: true, output: dp3, desktops: [desktops[2]] };
const workspace = {
    screens: [dp1, dp3],
    desktops,
    stackingOrder: [a, b],
    currentDesktopForScreen(output) {
        return output === dp1 ? desktops[1] : desktops[2];
    },
    windowAdded: signal(), windowRemoved: signal(),
    windowActivated: signal(), currentDesktopChanged: signal(),
    desktopsChanged: signal(), screensChanged: signal()
};
const calls = [];
vm.runInNewContext(source, {
    workspace,
    callDBus(...args) { calls.push(args); }
}, { filename: "state-publisher.js" });
assert.equal(calls.length, 1);
const state = JSON.parse(calls[0][4]);
assert.equal(state.version, 1);
assert.equal(state.outputs[0].name, "DP-1");
assert.equal(state.outputs[0].active, "2");
assert.deepEqual(Array.from(state.outputs[0].occupied), ["2"]);
assert.equal(state.outputs[1].active, "3");
workspace.windowActivated.emit(a);
assert.equal(calls.length, 1, "unchanged focus should not trigger more updates");
const c = { normalWindow: true, output: dp1, desktops: [desktops[2]] };
workspace.stackingOrder.push(c);
workspace.windowAdded.emit(c);
assert.equal(calls.length, 2);
assert.deepEqual(Array.from(JSON.parse(calls.at(-1)[4]).outputs[0].occupied), ["2", "3"]);
console.log("PASS: KWin state publisher per-output active/occupied and de-duplication");
