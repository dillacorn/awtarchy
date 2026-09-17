import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property bool enabled
    required property string units
    property string summary: ""

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string cachePath: root.cacheHome
        + "/awtarchy/lockscreen-weather.json"

    function normalizedUnits(value) {
        const mode = String(value || "auto");
        return ["auto", "fahrenheit", "celsius"].indexOf(mode) >= 0 ? mode : "auto";
    }

    function selectedEntry(parsed) {
        if (parsed.entries && typeof parsed.entries === "object"
                && !Array.isArray(parsed.entries)) {
            const selected = parsed.entries[root.units];
            if (selected && typeof selected === "object" && !Array.isArray(selected))
                return selected;
            return null;
        }
        // Backward compatibility for a pre-monitor Shared-only cache.
        return typeof parsed.summary === "string" ? parsed : null;
    }

    function refreshCache() {
        if (!root.enabled) {
            root.summary = "";
            return;
        }

        const text = cacheFile.text();
        if (!text || text.length === 0) {
            root.summary = "";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                root.summary = "";
                return;
            }

            const mode = root.normalizedUnits(root.units);
            const entry = parsed.entries && typeof parsed.entries === "object"
                ? parsed.entries[mode] : root.selectedEntry(parsed);
            if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                root.summary = "";
                return;
            }

            const value = typeof entry.summary === "string"
                ? entry.summary.trim() : "";
            const expiresAt = Number(entry.expires_at);
            const provider = typeof entry.provider === "string"
                ? entry.provider : "";
            const now = Math.floor(Date.now() / 1000);

            if (value.length === 0 || Array.from(value).length > 96
                    || !Number.isFinite(expiresAt) || expiresAt <= now
                    || provider !== "open-meteo") {
                root.summary = "";
                return;
            }

            root.summary = value;
        } catch (error) {
            root.summary = "";
        }
    }

    onEnabledChanged: {
        if (root.enabled)
            cacheFile.reload();
        else
            root.summary = "";
    }
    onUnitsChanged: {
        if (root.enabled)
            root.refreshCache();
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refreshCache()
        onFileChanged: root.refreshCache()
    }
}
