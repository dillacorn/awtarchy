#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = relativePath => fs.readFileSync(path.join(root, relativePath), "utf8");

const scenePath = "config/quickshell/awtarchy-lock/LockScene.qml";
const previewScenePath = "config/quickshell/awtarchy/LockPreviewScene.qml";
const analyzerPath = "config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml";
const previewAnalyzerPath = "config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml";
const surfacePath = "config/quickshell/awtarchy-lock/LockSurface.qml";
const editorPath = "config/quickshell/awtarchy/LockscreenEditor.qml";
const themePath = "config/quickshell/awtarchy-lock/LockTheme.qml";
const lockShellPath = "config/quickshell/awtarchy-lock/shell.qml";
const contrastPath = "config/quickshell/awtarchy-lock/LockContrastCache.qml";
const desktopShellPath = "config/quickshell/awtarchy/shell.qml";

const scene = read(scenePath);
const previewScene = read(previewScenePath);
const analyzer = read(analyzerPath);
const previewAnalyzer = read(previewAnalyzerPath);
const surface = read(surfacePath);
const editor = read(editorPath);
const theme = read(themePath);
const lockShell = read(lockShellPath);
const contrast = read(contrastPath);
const desktopShell = read(desktopShellPath);

function extractBalancedBlock(source, marker) {
    const markerIndex = source.indexOf(marker);
    assert.notEqual(markerIndex, -1, `missing source marker: ${marker}`);
    const openIndex = source.indexOf("{", markerIndex + marker.length);
    assert.notEqual(openIndex, -1, `missing opening brace after: ${marker}`);

    let depth = 0;
    let quote = "";
    let escaped = false;
    for (let index = openIndex; index < source.length; ++index) {
        const character = source[index];
        if (quote.length > 0) {
            if (escaped) {
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === quote) {
                quote = "";
            }
            continue;
        }
        if (character === "\"" || character === "'" || character === "`") {
            quote = character;
            continue;
        }
        if (character === "{") depth++;
        if (character === "}" && --depth === 0)
            return source.slice(markerIndex, index + 1);
    }
    assert.fail(`unterminated source block: ${marker}`);
}

function countOccurrences(source, needle) {
    return source.split(needle).length - 1;
}

function testAnalyzerParserAvoidsTemporaryFieldArray() {
    const clampUnit = extractBalancedBlock(analyzer, "function clampUnit(value)");
    const threshold = extractBalancedBlock(analyzer, "function threshold(value)");
    const parseFrame = extractBalancedBlock(analyzer, "function parseFrame(data)");
    const buildAnalyzer = new Function(`
        let bands = [];
        const maximumBands = 64;
        const silenceThreshold = 0.018;
        ${clampUnit}
        ${threshold}
        ${parseFrame}
        return { parseFrame, bands: () => bands };
    `);
    const runtime = buildAnalyzer();
    const originalSplit = String.prototype.split;
    let delimiterSplitCalls = 0;
    String.prototype.split = function(separator, limit) {
        if (separator === ";") delimiterSplitCalls++;
        return originalSplit.call(this, separator, limit);
    };
    try {
        runtime.parseFrame("0;18;19;1000;;500;\n");
    } finally {
        String.prototype.split = originalSplit;
    }

    assert.equal(delimiterSplitCalls, 0,
        "CAVA parsing allocated a temporary semicolon-split field array");
    const bands = runtime.bands();
    assert.equal(bands.length, 64);
    assert.deepEqual(bands.slice(0, 6), [0, 0.018, 0.019, 1, 0.5, 0]);
    assert.ok(bands.slice(5).every(value => value === 0));

    runtime.parseFrame("bad;2000");
    assert.deepEqual(runtime.bands().slice(0, 3), [0, 1, 0]);

    function referenceThreshold(value) {
        const numeric = Number(value);
        const bounded = Number.isFinite(numeric)
            ? Math.max(0, Math.min(1, numeric)) : 0;
        return bounded < 0.018 ? 0 : bounded;
    }
    function referenceParseFrame(data, previousBands) {
        const fields = String(data || "").trim().split(";");
        const result = [];
        for (let index = 0; index < fields.length && result.length < 64; ++index) {
            if (fields[index].length === 0)
                continue;
            result.push(referenceThreshold(Number(fields[index]) / 1000));
        }
        if (result.length === 0)
            return previousBands;
        while (result.length < 64)
            result.push(0);
        return result;
    }

    const corpus = [
        "", ";", ";;", " 0 ; 18;19 ;1000;;500; \n",
        "NaN;Infinity;-Infinity;2000;-4", 0, null, undefined,
        Array.from({ length: 70 }, (_, index) => String(index * 17)).join(";")
    ];
    const tokens = [
        "", "0", "17", "18", "19", "1000", "2000", "-1",
        "bad", "NaN", "Infinity", " 500 ", "1e3", "0x10"
    ];
    let seed = 0x5eed1234;
    const random = () => {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        return seed;
    };
    for (let frameIndex = 0; frameIndex < 2048; ++frameIndex) {
        const fields = [];
        const fieldCount = random() % 80;
        for (let fieldIndex = 0; fieldIndex < fieldCount; ++fieldIndex)
            fields.push(tokens[random() % tokens.length]);
        corpus.push(fields.join(";") + (random() % 2 === 0 ? ";" : ""));
    }

    let referenceBands = runtime.bands();
    for (const frame of corpus) {
        referenceBands = referenceParseFrame(frame, referenceBands);
        runtime.parseFrame(frame);
        assert.deepEqual(runtime.bands(), referenceBands,
            `direct CAVA parser diverged for frame ${JSON.stringify(frame)}`);
    }
}

function testLogoBucketBuildAvoidsPerParticleArrayCopies() {
    const rebuildLogoBuckets = extractBalancedBlock(scene, "function rebuildLogoBuckets()");
    const buildBuckets = new Function(`
        const logoParticles = {
            first: { row: 0, column: 0, x: 0, y: 0 },
            second: { row: 0, column: 1, x: 0, y: 0 },
            third: { row: 1, column: 0, x: 0, y: 0 }
        };
        const wordmarkCellWidth = 10;
        const wordmarkCellHeight = 10;
        const logoExplosionBucketSize = 100;
        let logoParticleBuckets = {};
        ${rebuildLogoBuckets}
        rebuildLogoBuckets();
        return logoParticleBuckets;
    `);

    const originalSlice = Array.prototype.slice;
    let sliceCalls = 0;
    Array.prototype.slice = function(...args) {
        sliceCalls++;
        return originalSlice.apply(this, args);
    };
    let buckets;
    try {
        buckets = buildBuckets();
    } finally {
        Array.prototype.slice = originalSlice;
    }

    assert.equal(sliceCalls, 0,
        "logo bucket construction copied an existing member array");
    assert.deepEqual(buckets, { "0:0": ["first", "second", "third"] });
}

function testLockThemeReadsCachedParsedData() {
    const value = extractBalancedBlock(theme, "function value(name, fallback)");
    const evaluateValues = new Function(`
        let parseReads = 0;
        function themeData() {
            parseReads++;
            return { dark: "#111111", foreground: "#eeeeee" };
        }
        const root = {
            parsedTheme: { dark: "#111111", foreground: "#eeeeee" }
        };
        ${value}
        const values = [
            value("dark", "#000000"),
            value("foreground", "#d0d0d0"),
            value("muted", "#666666")
        ];
        return { parseReads, values };
    `);
    const result = evaluateValues();
    assert.equal(result.parseReads, 0,
        "each lock-theme color access reparsed theme.json");
    assert.deepEqual(result.values, ["#111111", "#eeeeee", "#666666"]);
    assert.match(theme, /readonly property var parsedTheme:\s*themeData\(\)/,
        "LockTheme does not synchronously populate its single parsed cache");
    assert.equal(theme.includes("onLoaded: root.refreshTheme()"), false,
        "LockTheme defers its initial theme cache until asynchronous preload completion");
}

function testExternalTransitionLayerIsTheOnlySceneRenderer() {
    for (const source of [scene, previewScene]) {
        for (const obsolete of [
            "function replayEntryTransition()",
            "id: entryFadeBacking",
            "id: entryTransitionCover",
            "id: entryTransitionAnimation",
            "property bool externallyManagedEntryTransition",
            "property real externalEntryTransitionProgress"
        ]) {
            assert.equal(source.includes(obsolete), false,
                `shared scene still contains obsolete internal transition code: ${obsolete}`);
        }
    }

    assert.equal(countOccurrences(surface, "LockScene {"), 1);
    const secureScene = extractBalancedBlock(surface, "LockScene {");
    assert.match(secureScene, /externalEntryTransitionRunning:\s*transitionLayer\.running/);

    assert.equal(countOccurrences(editor, "LockPreviewScene {"), 2);
    const primaryPreview = extractBalancedBlock(editor, "LockPreviewScene {");
    const secondaryStart = editor.indexOf("LockPreviewScene {",
        editor.indexOf("LockPreviewScene {") + 1);
    const secondaryPreview = extractBalancedBlock(editor.slice(secondaryStart), "LockPreviewScene {");
    assert.match(primaryPreview, /externalEntryTransitionRunning:\s*editorTransitionLayer\.running/);
    assert.match(secondaryPreview, /externalEntryTransitionRunning:\s*secondaryPreviewTransitionLayer\.running/);
}

function testBlockingStartupFilesAreParsedOnce() {
    assert.match(lockShell, /Component\.onCompleted:\s*\{[\s\S]*root\.loadPreferences\(\)/);
    assert.equal(/onLoaded:\s*root\.loadPreferences\(\)/.test(lockShell), false,
        "secure preferences are parsed from both Component.onCompleted and FileView.onLoaded");

    assert.match(contrast, /Component\.onCompleted:\s*root\.refresh\(\)/);
    assert.equal(/onLoaded:\s*root\.refresh\(\)/.test(contrast), false,
        "secure contrast cache is parsed from both Component.onCompleted and FileView.onLoaded");
}

function testDesktopContrastSingletonUsesExplicitReadinessReference() {
    assert.match(desktopShell,
        /readonly property bool lockscreenContrastReady:\s*LockscreenContrast !== null/);
    assert.equal(desktopShell.includes("LockscreenContrast.accent"), false,
        "desktop shell still reads the retired scalar contrast property");
}

const tests = [
    ["CAVA parser allocation", testAnalyzerParserAvoidsTemporaryFieldArray],
    ["logo bucket allocation", testLogoBucketBuildAvoidsPerParticleArrayCopies],
    ["lock-theme parse cache", testLockThemeReadsCachedParsedData],
    ["external transition ownership", testExternalTransitionLayerIsTheOnlySceneRenderer],
    ["single blocking startup parse", testBlockingStartupFilesAreParsedOnce],
    ["desktop contrast readiness", testDesktopContrastSingletonUsesExplicitReadinessReference]
];
let failures = 0;
for (const [name, test] of tests) {
    try {
        test();
    } catch (error) {
        failures++;
        console.error(`FAIL: ${name}: ${error.message}`);
    }
}

try {
    assert.equal(scene, previewScene, "secure/editor scene parity is broken");
    assert.equal(analyzer, previewAnalyzer, "secure/editor analyzer parity is broken");
} catch (error) {
    failures++;
    console.error(`FAIL: parity: ${error.message}`);
}

assert.equal(failures, 0, `${failures} lockscreen efficiency contract(s) failed`);

console.log("PASS: lockscreen deterministic efficiency contracts");
