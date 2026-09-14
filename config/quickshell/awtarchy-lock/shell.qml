//@ pragma ShellId awtarchy-lock
//@ pragma CacheDir $BASE/awtarchy-lock
//@ pragma StateDir $BASE/awtarchy-lock

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "LockscreenPresentationState.js" as LockscreenPresentationState

ShellRoot {
    id: root

    property bool unlockRequested: false
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string captureHelper: configHome
        + "/hypr/scripts/quickshell_lockscreen_capture.sh"
    readonly property string timezoneHelper: configHome
        + "/hypr/scripts/quickshell_lockscreen_timezones.sh"
    readonly property string captureDirectory: normalizedCaptureDirectory(
        Quickshell.env("AWTARCHY_LOCK_CAPTURE_DIR") || "")
    property bool captureCleanupRequested: false
    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    property string lockAnimationPreference: "split"
    property string lockEntryTransition: "fade"
    property int lockEntryTransitionDuration: 1800
    property int lockLogoPhysicsHz: 30
    property bool lockMouseInteractive: true
    property bool lockShowLogo: true
    property bool lockShowTime: false
    property bool lockShowDate: false
    property bool lockShowUsername: false
    property bool lockShowWeather: false
    property string lockPasswordMaskMode: "squares"
    property string lockPasswordMaskCharacter: "•"
    property string lockClockFormat: "24h"
    property string lockBackground: "black"
    property color lockBackgroundColor: "#000000"
    property string lockWallpaperPath: ""
    property string lockWallpaperFit: "cover"
    property real lockWallpaperFocalX: 0.5
    property real lockWallpaperFocalY: 0.5
    property string lockOverlayMode: "none"
    property int lockOverlayStrength: 0
    property int lockWallpaperBlur: 0
    property string lockBlurStyle: "smooth"
    property string lockWeatherLocation: ""
    readonly property string wallpaperFit: normalizedWallpaperFit(lockWallpaperFit)
    readonly property real wallpaperFocalX: normalizedUnitInterval(lockWallpaperFocalX, 0.5)
    readonly property real wallpaperFocalY: normalizedUnitInterval(lockWallpaperFocalY, 0.5)
    readonly property string overlayMode: normalizedOverlayMode(lockOverlayMode)
    readonly property int overlayStrength: normalizedPercent(lockOverlayStrength)
    readonly property int wallpaperBlur: normalizedPercent(lockWallpaperBlur)
    readonly property string blurStyle: normalizedBlurStyle(lockBlurStyle)
    property var lockLayout: defaultLockLayout()
    property var lockCustomImages: []
    property var lockTimezoneClocks: []
    property var lockTimezoneValues: ({})
    property var lockCustomTexts: []
    property var lockVisualizer: defaultLockVisualizer()
    property int lockBackgroundOpacity: 100
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function normalizedCaptureDirectory(value) {
        const path = String(value || "");
        if (root.runtimeDir.length === 0)
            return "";
        const prefix = root.runtimeDir + "/awtarchy-lock-transition/capture.";
        if (!path.startsWith(prefix))
            return "";
        const suffix = path.slice(prefix.length);
        return /^[A-Za-z0-9]+$/.test(suffix) ? path : "";
    }

    function cleanupTransitionCapture() {
        if (root.captureCleanupRequested || root.captureDirectory.length === 0)
            return;
        root.captureCleanupRequested = true;
        Quickshell.execDetached([root.captureHelper, "cleanup", root.captureDirectory]);
    }

    function defaultLockVisualizer() {
        return ({
            enabled: false,
            x: 0.50,
            y: 0.80,
            scale: 1.0,
            stretch_x: 1.0,
            stretch_y: 1.0,
            opacity: 100,
            rotation: 0,
            color: "auto",
            bands: 16,
            gap: 4,
            height: 100,
            sensitivity: 180,
            shape: "straight",
            bend: 45,
            performance: "balanced"
        });
    }

    function normalizedVisualizer(value) {
        const defaults = defaultLockVisualizer();
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        const enabled = typeof value.enabled === "boolean" ? value.enabled : defaults.enabled;
        const x = Number(value.x === undefined ? defaults.x : value.x);
        const y = Number(value.y === undefined ? defaults.y : value.y);
        const scale = Number(value.scale === undefined ? defaults.scale : value.scale);
        const stretchX = Number(value.stretch_x === undefined ? defaults.stretch_x : value.stretch_x);
        const stretchY = Number(value.stretch_y === undefined ? defaults.stretch_y : value.stretch_y);
        const opacity = Number(value.opacity === undefined ? defaults.opacity : value.opacity);
        const rotation = Number(value.rotation === undefined ? defaults.rotation : value.rotation);
        const color = String(value.color === undefined ? defaults.color : value.color).toLowerCase();
        const bands = Number(value.bands === undefined ? defaults.bands : value.bands);
        const gap = Number(value.gap === undefined ? defaults.gap : value.gap);
        const responseHeight = Number(value.height === undefined ? defaults.height : value.height);
        const sensitivity = Number(value.sensitivity === undefined ? defaults.sensitivity : value.sensitivity);
        const shape = String(value.shape === undefined ? defaults.shape : value.shape);
        const bend = Number(value.bend === undefined ? defaults.bend : value.bend);
        const performance = String(value.performance === undefined ? defaults.performance : value.performance);
        if (!Number.isFinite(x) || x < 0.05 || x > 0.95
                || !Number.isFinite(y) || y < 0.08 || y > 0.92
                || !Number.isFinite(scale) || scale < 0.50 || scale > 100.00
                || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00
                || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00
                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))
                || !Number.isInteger(bands) || bands < 4 || bands > 64
                || !Number.isInteger(gap) || gap < 0 || gap > 24
                || !Number.isInteger(responseHeight) || responseHeight < 25 || responseHeight > 300
                || !Number.isInteger(sensitivity) || sensitivity < 25 || sensitivity > 300
                || ["straight", "arc", "circle"].indexOf(shape) < 0
                || ["balanced", "responsive", "high"].indexOf(performance) < 0
                || !Number.isInteger(bend) || bend < -2000 || bend > 2000)
            return defaults;
        return ({
            enabled: enabled,
            x: x,
            y: y,
            scale: scale,
            stretch_x: stretchX,
            stretch_y: stretchY,
            opacity: opacity,
            rotation: rotation,
            color: color,
            bands: bands,
            gap: gap,
            height: responseHeight,
            sensitivity: sensitivity,
            shape: shape,
            bend: bend,
            performance: performance
        });
    }

    function normalizedBackgroundOpacity(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric) || !Number.isInteger(numeric)
                || numeric < 0 || numeric > 100)
            return 100;
        return numeric;
    }

    function defaultLockLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto" })
        });
    }

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "split";
    }

    function normalizedEntryTransition(value) {
        const key = String(value || "");
        return ["fade", "pixel", "edges", "wipe"].indexOf(key) >= 0
            ? key : "fade";
    }

    function normalizedEntryTransitionDuration(value) {
        const numeric = Math.round(Number(value));
        return Number.isFinite(numeric)
            ? Math.max(800, Math.min(6000, numeric)) : 1800;
    }

    function normalizedLogoPhysicsHz(value) {
        const numeric = Math.round(Number(value));
        return [30, 60, 90].indexOf(numeric) >= 0 ? numeric : 30;
    }

    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
    }

    function normalizedPasswordMaskMode(value) {
        const key = String(value || "");
        return ["squares", "dots", "custom"].indexOf(key) >= 0 ? key : "squares";
    }

    function normalizedPasswordMaskCharacter(value) {
        const text = String(value || "").trim();
        if (text.length === 0 || /[\u0000-\u001f\u007f-\u009f]/.test(text))
            return "•";
        const points = Array.from(text);
        return points.length === 1 ? points[0] : "•";
    }

    function normalizedClockFormat(value) {
        const key = String(value || "");
        return ["24h", "12h"].indexOf(key) >= 0 ? key : "24h";
    }

    function normalizedBackground(value) {
        const key = String(value || "");
        return ["black", "wallpaper", "color"].indexOf(key) >= 0 ? key : "black";
    }

    function normalizedBackgroundColor(value) {
        const key = String(value || "#000000").toLowerCase();
        return /^#[0-9a-f]{6}$/.test(key) ? key : "#000000";
    }

    function normalizedWallpaperFit(value) {
        const key = String(value || "");
        return ["cover", "contain"].indexOf(key) >= 0 ? key : "cover";
    }

    function normalizedOverlayMode(value) {
        const key = String(value || "");
        return ["none", "dark", "light"].indexOf(key) >= 0 ? key : "none";
    }

    function normalizedBlurStyle(value) {
        const key = String(value || "");
        return ["smooth", "pixelated"].indexOf(key) >= 0 ? key : "smooth";
    }

    function normalizedUnitInterval(value, fallback) {
        const numeric = Number(value);
        return Number.isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : fallback;
    }

    function normalizedPercent(value) {
        const numeric = Number(value);
        return Number.isFinite(numeric) ? Math.max(0, Math.min(100, Math.round(numeric))) : 0;
    }

    function normalizedWallpaperPath(value) {
        const path = typeof value === "string" ? value : "";
        if (!path.startsWith("/") || path.indexOf("://") >= 0
                || /[\u0000-\u001f\u007f-\u009f]/.test(path))
            return "";
        return path;
    }

    function layoutPoint(value, fallback, password) {
        const fallbackColor = String(fallback.color || "auto");
        const fallbackOpacity = Number(fallback.opacity === undefined ? 100 : fallback.opacity);
        const fallbackRotation = Number(fallback.rotation === undefined ? 0 : fallback.rotation);
        if (!value || typeof value !== "object" || Array.isArray(value))
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, rotation: fallbackRotation, color: fallbackColor });
        const x = Number(value.x);
        const y = Number(value.y);
        const scale = Number(value.scale === undefined ? 1 : value.scale);
        const stretchX = Number(value.stretch_x === undefined ? 1 : value.stretch_x);
        const stretchY = Number(value.stretch_y === undefined ? 1 : value.stretch_y);
        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);
        const rotation = Number(value.rotation === undefined ? 0 : value.rotation);
        const rawColor = String(value.color === undefined ? "auto" : value.color);
        const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)
            ? rawColor.toLowerCase() : fallbackColor;
        const minX = password ? 0.15 : 0.05;
        const maxX = password ? 0.85 : 0.95;
        const minY = password ? 0.20 : 0.08;
        const maxY = password ? 0.86 : 0.92;
        const minOpacity = password ? 20 : 0;
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(scale)
                || !Number.isFinite(stretchX) || !Number.isFinite(stretchY)
                || !Number.isFinite(opacity) || !Number.isFinite(rotation)
                || x < minX || x > maxX || y < minY || y > maxY
                || scale < 0.50 || scale > 100.00
                || stretchX < 0.25 || stretchX > 4.00
                || stretchY < 0.25 || stretchY > 4.00
                || opacity < minOpacity || opacity > 100
                || rotation < -180 || rotation > 180)
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, rotation: fallbackRotation, color: fallbackColor });
        return ({ x: x, y: y, scale: scale, stretch_x: stretchX, stretch_y: stretchY, opacity: opacity, rotation: rotation, color: color });
    }
    function normalizedLayout(value) {
        const defaults = defaultLockLayout();
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        return ({
            logo: layoutPoint(value.logo, defaults.logo, false),
            time: layoutPoint(value.time, defaults.time, false),
            date: layoutPoint(value.date, defaults.date, false),
            username: layoutPoint(value.username, defaults.username, false),
            weather: layoutPoint(value.weather, defaults.weather, false),
            password: layoutPoint(value.password, defaults.password, true)
        });
    }

    function normalizedCustomImageSpawn(value) {
        const key = String(value === undefined ? "none" : value);
        return ["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"].indexOf(key) >= 0
            ? key : "none";
    }

    function normalizedCustomImages(value) {
        if (!Array.isArray(value) || value.length > 12)
            return [];
        const result = [];
        const ids = ({});
        for (let i = 0; i < value.length; ++i) {
            const image = value[i];
            if (!image || typeof image !== "object" || Array.isArray(image))
                return [];
            const id = String(image.id || "");
            const path = normalizedWallpaperPath(image.path);
            const x = Number(image.x);
            const y = Number(image.y);
            const scale = Number(image.scale);
            const stretchX = Number(image.stretch_x);
            const stretchY = Number(image.stretch_y);
            const opacity = Number(image.opacity);
            const rotation = Number(image.rotation === undefined ? 0 : image.rotation);
            const spawnAnimation = normalizedCustomImageSpawn(image.spawn_animation);
            const spawnTiming = LockscreenPresentationState.normalizeSpawnTiming(image.spawn_timing);
            if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || path.length === 0
                    || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92
                    || !Number.isFinite(scale) || scale < 0.50 || scale > 100.00
                    || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00
                    || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                    || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || typeof image.visible !== "boolean")
                return [];
            ids[id] = true;
            result.push(({
                id: id, path: path, x: x, y: y, scale: scale,
                stretch_x: stretchX, stretch_y: stretchY, opacity: opacity,
                rotation: rotation, spawn_animation: spawnAnimation, spawn_timing: spawnTiming,
                visible: image.visible
            }));
        }
        return result;
    }

    function normalizedTimezoneClocks(value) {
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""), timezone = String(raw.timezone || "UTC");
            const format = String(raw.format || "24h") === "12h" ? "12h" : "24h";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale), sx = Number(raw.stretch_x), sy = Number(raw.stretch_y);
            const opacity = Number(raw.opacity), rotation = Number(raw.rotation), color = String(raw.color || "auto").toLowerCase();
            if (!/^timezone-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || timezone.startsWith("/") || timezone.indexOf("..") >= 0
                    || /[\u0000-\u001f\u007f-\u009f]/.test(timezone) || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92 || !Number.isFinite(scale) || scale < 0.5 || scale > 100
                    || !Number.isFinite(sx) || sx < 0.25 || sx > 4 || !Number.isFinite(sy) || sy < 0.25 || sy > 4
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100 || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id:id, timezone:timezone, format:format, x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy,
                opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));
        }
        return result;
    }

    function normalizedCustomTexts(value) {
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""), text = String(raw.text === undefined ? "Custom Text" : raw.text);
            const variants = Array.isArray(raw.variants) ? raw.variants.map(value => String(value)) : [];
            const alignment = ["left","center","right"].indexOf(String(raw.alignment)) >= 0 ? String(raw.alignment) : "center";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale), sx = Number(raw.stretch_x), sy = Number(raw.stretch_y);
            const opacity = Number(raw.opacity), rotation = Number(raw.rotation), color = String(raw.color || "auto").toLowerCase();
            if (!/^text-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || text.length > 4096 || variants.length > 32
                    || variants.some(value => value.length > 4096) || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92 || !Number.isFinite(scale) || scale < 0.5 || scale > 100
                    || !Number.isFinite(sx) || sx < 0.25 || sx > 4 || !Number.isFinite(sy) || sy < 0.25 || sy > 4
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100 || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id:id, text:text, variants:variants, randomize:raw.randomize === true, alignment:alignment,
                x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy, opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));
        }
        return result;
    }

    function timezoneHelperArgs() {
        const args = ["bash", root.timezoneHelper, "--batch"];
        for (const clock of root.lockTimezoneClocks)
            args.push(String(clock.id), String(clock.timezone), String(clock.format));
        return args;
    }

    function refreshTimezoneValues() {
        if (root.lockTimezoneClocks.length === 0) { root.lockTimezoneValues = ({}); return; }
        if (!timezoneProcess.running) timezoneProcess.exec(root.timezoneHelperArgs());
    }

    function applyTimezoneValues(line) {
        try { const value = JSON.parse(String(line || "")); if (value && typeof value === "object" && !Array.isArray(value)) root.lockTimezoneValues = value; }
        catch (error) { }
    }

    function normalizedWeatherLocation(value) {
        if (typeof value !== "string")
            return "";
        const trimmed = value.trim();
        if (Array.from(trimmed).length > 96 || /[\u0000-\u001f\u007f-\u009f]/.test(trimmed))
            return "";
        return trimmed;
    }

    function resetPreferences() {
        lockAnimationPreference = "split";
        lockEntryTransition = "fade";
        lockEntryTransitionDuration = 1800;
        lockLogoPhysicsHz = 30;
        lockMouseInteractive = true;
        lockShowLogo = true;
        lockShowTime = false;
        lockShowDate = false;
        lockShowUsername = false;
        lockShowWeather = false;
        lockPasswordMaskMode = "squares";
        lockPasswordMaskCharacter = "•";
        lockClockFormat = "24h";
        lockBackground = "black";
        lockBackgroundColor = "#000000";
        lockWallpaperPath = "";
        lockWallpaperFit = "cover";
        lockWallpaperFocalX = 0.5;
        lockWallpaperFocalY = 0.5;
        lockOverlayMode = "none";
        lockOverlayStrength = 0;
        lockWallpaperBlur = 0;
        lockBlurStyle = "smooth";
        lockWeatherLocation = "";
        lockLayout = defaultLockLayout();
        lockCustomImages = [];
        lockTimezoneClocks = [];
        lockTimezoneValues = ({});
        lockCustomTexts = [];
        lockVisualizer = defaultLockVisualizer();
        lockBackgroundOpacity = 100;
    }

    function loadPreferences() {
        const text = stateFile.text();
        if (!text || text.length === 0) {
            resetPreferences();
            return;
        }

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                resetPreferences();
                return;
            }

            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockEntryTransition = normalizedEntryTransition(parsed.lockscreen_entry_transition);
            lockEntryTransitionDuration = normalizedEntryTransitionDuration(
                parsed.lockscreen_entry_transition_duration);
            lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);
            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);
            lockShowLogo = normalizedBoolean(parsed.lockscreen_show_logo, true);
            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);
            lockShowDate = normalizedBoolean(parsed.lockscreen_show_date, false);
            lockShowUsername = normalizedBoolean(parsed.lockscreen_show_username, false);
            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
            lockPasswordMaskMode = normalizedPasswordMaskMode(parsed.lockscreen_password_mask_mode);
            lockPasswordMaskCharacter = normalizedPasswordMaskCharacter(parsed.lockscreen_password_mask_character);
            lockClockFormat = normalizedClockFormat(parsed.lockscreen_clock_format);
            lockBackground = normalizedBackground(parsed.lockscreen_background);
            lockBackgroundColor = normalizedBackgroundColor(parsed.lockscreen_background_color);
            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWallpaperFit = normalizedWallpaperFit(parsed.lockscreen_wallpaper_fit);
            lockWallpaperFocalX = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_x, 0.5);
            lockWallpaperFocalY = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_y, 0.5);
            lockOverlayMode = normalizedOverlayMode(parsed.lockscreen_overlay_mode);
            lockOverlayStrength = normalizedPercent(parsed.lockscreen_overlay_strength);
            lockWallpaperBlur = normalizedPercent(parsed.lockscreen_wallpaper_blur);
            lockBlurStyle = normalizedBlurStyle(parsed.lockscreen_blur_style);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
            lockLayout = normalizedLayout(parsed.lockscreen_layout);
            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);
            lockTimezoneClocks = normalizedTimezoneClocks(parsed.lockscreen_timezone_clocks);
            lockCustomTexts = normalizedCustomTexts(parsed.lockscreen_custom_texts);
            lockVisualizer = normalizedVisualizer(parsed.lockscreen_visualizer);
            lockBackgroundOpacity = normalizedBackgroundOpacity(parsed.lockscreen_background_opacity);
        } catch (error) {
            resetPreferences();
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        root.loadPreferences();
        Qt.callLater(root.refreshTimezoneValues);
    }

    Process {
        id: timezoneProcess
        stdout: SplitParser { onRead: line => root.applyTimezoneValues(line) }
    }
    Timer { interval: 15000; repeat: true; running: root.lockTimezoneClocks.length > 0; triggeredOnStart: true; onTriggered: root.refreshTimezoneValues() }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
    }

    LockTheme {
        id: lockTheme
    }

    LockAuth {
        id: lockAuth

        onAuthenticated: {
            if (root.unlockRequested)
                return;

            root.unlockRequested = true;
            unlockFadeTimer.restart();
        }
    }

    LockWeatherCache {
        id: lockWeatherCache
        enabled: root.lockShowWeather
    }

    LockWallpaperState {
        id: lockWallpaperState
        path: root.lockWallpaperPath
    }

    LockContrastCache {
        id: lockContrastCache
    }

    LockAudioAnalyzer {
        id: lockAudioAnalyzer
        enabled: root.lockVisualizer.enabled
        performanceMode: root.lockVisualizer.performance
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        surface: Component {
            LockSurface {
                auth: lockAuth
                theme: lockTheme
                unlocking: root.unlockRequested
                animationPreference: root.lockAnimationPreference
                entryTransition: root.lockEntryTransition
                entryTransitionDuration: root.lockEntryTransitionDuration
                randomFormationMode: root.randomFormationMode
                logoPhysicsHz: root.lockLogoPhysicsHz
                mouseInteractive: root.lockMouseInteractive
                showLogo: root.lockShowLogo
                showTime: root.lockShowTime
                showDate: root.lockShowDate
                showUsername: root.lockShowUsername
                showWeather: root.lockShowWeather
                weatherText: lockWeatherCache.summary
                backgroundMode: root.lockBackground
                wallpaperSource: lockWallpaperState.source
                backgroundColor: root.lockBackgroundColor
                wallpaperFit: root.wallpaperFit
                wallpaperFocalX: root.wallpaperFocalX
                wallpaperFocalY: root.wallpaperFocalY
                overlayMode: root.overlayMode
                overlayStrength: root.overlayStrength
                wallpaperBlur: root.wallpaperBlur
                blurStyle: root.blurStyle
                autoAccents: lockContrastCache.colors
                layout: root.lockLayout
                customImages: root.lockCustomImages
                timezoneClocks: root.lockTimezoneClocks
                timezoneValues: root.lockTimezoneValues
                customTexts: root.lockCustomTexts
                visualizer: root.lockVisualizer
                audioBands: lockAudioAnalyzer.bands
                backgroundOpacity: root.lockBackgroundOpacity
                passwordMaskMode: root.lockPasswordMaskMode
                passwordMaskCharacter: root.lockPasswordMaskCharacter
                clockFormat: root.lockClockFormat
                captureDirectory: root.captureDirectory
            }
        }

        onSecureChanged: {
            if (secure && root.captureDirectory.length > 0)
                captureCleanupTimer.restart();
            if (root.unlockRequested && !secure) {
                root.cleanupTransitionCapture();
                quitAfterUnlock.restart();
            }
        }
    }

    IpcHandler {
        target: "lock"

        function state(): string {
            return sessionLock.secure ? "secure"
                : sessionLock.locked ? "starting" : "unlocked";
        }

        function stopTest(): bool {
            if (sessionLock.secure)
                return false;

            root.unlockRequested = true;
            sessionLock.locked = false;
            quitAfterUnlock.restart();
            return true;
        }
    }

    Timer {
        id: unlockFadeTimer
        interval: 170
        repeat: false
        onTriggered: {
            sessionLock.locked = false;
            if (!sessionLock.secure)
                quitAfterUnlock.restart();
        }
    }

    Timer {
        id: captureCleanupTimer
        interval: Math.max(3000, Math.min(8000, root.lockEntryTransitionDuration + 2000))
        repeat: false
        onTriggered: root.cleanupTransitionCapture()
    }

    Timer {
        id: quitAfterUnlock
        interval: 150
        repeat: false
        onTriggered: {
            root.cleanupTransitionCapture();
            Qt.quit();
        }
    }
}
