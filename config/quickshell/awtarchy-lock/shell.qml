//@ pragma ShellId awtarchy-lock
//@ pragma CacheDir $BASE/awtarchy-lock
//@ pragma StateDir $BASE/awtarchy-lock

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool unlockRequested: false
    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    property string lockAnimationPreference: "split"
    property int lockLogoPhysicsHz: 30
    property bool lockMouseInteractive: true
    property bool lockShowLogo: true
    property bool lockShowTime: false
    property bool lockShowDate: false
    property bool lockShowUsername: false
    property bool lockShowWeather: false
    property string lockBackground: "black"
    property color lockBackgroundColor: "#000000"
    property string lockWallpaperPath: ""
    property string lockWallpaperFit: "cover"
    property real lockWallpaperFocalX: 0.5
    property real lockWallpaperFocalY: 0.5
    property string lockOverlayMode: "none"
    property int lockOverlayStrength: 0
    property int lockWallpaperBlur: 0
    property string lockWeatherLocation: ""
    readonly property string wallpaperFit: normalizedWallpaperFit(lockWallpaperFit)
    readonly property real wallpaperFocalX: normalizedUnitInterval(lockWallpaperFocalX, 0.5)
    readonly property real wallpaperFocalY: normalizedUnitInterval(lockWallpaperFocalY, 0.5)
    readonly property string overlayMode: normalizedOverlayMode(lockOverlayMode)
    readonly property int overlayStrength: normalizedPercent(lockOverlayStrength)
    readonly property int wallpaperBlur: normalizedPercent(lockWallpaperBlur)
    property var lockLayout: defaultLockLayout()
    property var lockCustomImages: []
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function defaultLockLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" })
        });
    }

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "split";
    }

    function normalizedLogoPhysicsHz(value) {
        const numeric = Math.round(Number(value));
        return [30, 60, 90].indexOf(numeric) >= 0 ? numeric : 30;
    }

    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
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
        if (!value || typeof value !== "object" || Array.isArray(value))
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });
        const x = Number(value.x);
        const y = Number(value.y);
        const scale = Number(value.scale === undefined ? 1 : value.scale);
        const stretchX = Number(value.stretch_x === undefined ? 1 : value.stretch_x);
        const stretchY = Number(value.stretch_y === undefined ? 1 : value.stretch_y);
        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);
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
                || !Number.isFinite(opacity)
                || x < minX || x > maxX || y < minY || y > maxY
                || scale < 0.50 || scale > 2.00
                || stretchX < 0.25 || stretchX > 4.00
                || stretchY < 0.25 || stretchY > 4.00
                || opacity < minOpacity || opacity > 100)
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });
        return ({ x: x, y: y, scale: scale, stretch_x: stretchX, stretch_y: stretchY, opacity: opacity, color: color });
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
            if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || path.length === 0
                    || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92
                    || !Number.isFinite(scale) || scale < 0.50 || scale > 2.00
                    || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00
                    || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                    || typeof image.visible !== "boolean")
                return [];
            ids[id] = true;
            result.push(({
                id: id, path: path, x: x, y: y, scale: scale,
                stretch_x: stretchX, stretch_y: stretchY, opacity: opacity,
                visible: image.visible
            }));
        }
        return result;
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
        lockLogoPhysicsHz = 30;
        lockMouseInteractive = true;
        lockShowLogo = true;
        lockShowTime = false;
        lockShowDate = false;
        lockShowUsername = false;
        lockShowWeather = false;
        lockBackground = "black";
        lockBackgroundColor = "#000000";
        lockWallpaperPath = "";
        lockWallpaperFit = "cover";
        lockWallpaperFocalX = 0.5;
        lockWallpaperFocalY = 0.5;
        lockOverlayMode = "none";
        lockOverlayStrength = 0;
        lockWallpaperBlur = 0;
        lockWeatherLocation = "";
        lockLayout = defaultLockLayout();
        lockCustomImages = [];
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
            lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);
            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);
            lockShowLogo = normalizedBoolean(parsed.lockscreen_show_logo, true);
            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);
            lockShowDate = normalizedBoolean(parsed.lockscreen_show_date, false);
            lockShowUsername = normalizedBoolean(parsed.lockscreen_show_username, false);
            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
            lockBackground = normalizedBackground(parsed.lockscreen_background);
            lockBackgroundColor = normalizedBackgroundColor(parsed.lockscreen_background_color);
            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWallpaperFit = normalizedWallpaperFit(parsed.lockscreen_wallpaper_fit);
            lockWallpaperFocalX = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_x, 0.5);
            lockWallpaperFocalY = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_y, 0.5);
            lockOverlayMode = normalizedOverlayMode(parsed.lockscreen_overlay_mode);
            lockOverlayStrength = normalizedPercent(parsed.lockscreen_overlay_strength);
            lockWallpaperBlur = normalizedPercent(parsed.lockscreen_wallpaper_blur);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
            lockLayout = normalizedLayout(parsed.lockscreen_layout);
            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);
        } catch (error) {
            resetPreferences();
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        root.loadPreferences();
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
        onLoaded: root.loadPreferences()
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

    WlSessionLock {
        id: sessionLock
        locked: true

        surface: Component {
            LockSurface {
                auth: lockAuth
                theme: lockTheme
                unlocking: root.unlockRequested
                animationPreference: root.lockAnimationPreference
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
                autoAccents: lockContrastCache.colors
                layout: root.lockLayout
                customImages: root.lockCustomImages
            }
        }

        onSecureChanged: {
            if (root.unlockRequested && !secure)
                quitAfterUnlock.restart();
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
        id: quitAfterUnlock
        interval: 150
        repeat: false
        onTriggered: Qt.quit()
    }
}
