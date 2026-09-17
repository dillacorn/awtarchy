.pragma library

function clampNumber(value, fallback, minimum, maximum) {
    const number = Number(value);
    const safe = Number.isFinite(number) ? number : fallback;
    return Math.max(minimum, Math.min(maximum, safe));
}

function normalizedColor(value) {
    const color = String(value === undefined || value === null ? "auto" : value).toLowerCase();
    return color === "auto" || /^#[0-9a-f]{6}$/.test(color) ? color : "auto";
}

function normalizedRotation(value) {
    return clampNumber(value, 0, -180, 180);
}

function normalizedElement(value, fallbackX, fallbackY, minimumOpacity) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    return ({
        x: clampNumber(raw.x, fallbackX, 0.05, 0.95),
        y: clampNumber(raw.y, fallbackY, 0.08, 0.92),
        scale: clampNumber(raw.scale, 1, 0.50, 100),
        stretch_x: clampNumber(raw.stretch_x, 1, 0.25, 4),
        stretch_y: clampNumber(raw.stretch_y, 1, 0.25, 4),
        opacity: clampNumber(raw.opacity, 100, minimumOpacity === undefined ? 0 : minimumOpacity, 100),
        rotation: normalizedRotation(raw.rotation),
        color: normalizedColor(raw.color)
    });
}

function normalizeLayout(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    const password = normalizedElement(raw.password, 0.50, 0.70, 20);
    password.x = clampNumber(password.x, 0.50, 0.15, 0.85);
    password.y = clampNumber(password.y, 0.70, 0.20, 0.86);
    return ({
        logo: normalizedElement(raw.logo, 0.50, 0.34, 0),
        time: normalizedElement(raw.time, 0.50, 0.51, 0),
        date: normalizedElement(raw.date, 0.50, 0.555, 0),
        username: normalizedElement(raw.username, 0.50, 0.595, 0),
        weather: normalizedElement(raw.weather, 0.50, 0.635, 0),
        password: password
    });
}

function normalizeVisualizer(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    const normalized = normalizedElement(raw, 0.50, 0.80, 0);
    normalized.enabled = raw.enabled === true;
    normalized.bands = Math.round(clampNumber(raw.bands, 16, 4, 64));
    normalized.gap = Math.round(clampNumber(raw.gap, 4, 0, 24));
    normalized.height = Math.round(clampNumber(raw.height, 100, 25, 300));
    normalized.sensitivity = Math.round(clampNumber(raw.sensitivity, 180, 25, 300));
    normalized.shape = ["straight", "arc", "circle"].indexOf(String(raw.shape || "")) >= 0
        ? String(raw.shape) : "straight";
    normalized.bend = Math.round(clampNumber(raw.bend, 45, -2000, 2000));
    normalized.performance = ["balanced", "responsive", "high"].indexOf(String(raw.performance || "")) >= 0
        ? String(raw.performance) : "balanced";
    return normalized;
}

function normalizeSpawnAnimation(value) {
    const key = String(value === undefined ? "none" : value);
    return ["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"].indexOf(key) >= 0
        ? key : "none";
}

function normalizeSpawnTiming(value) {
    return String(value || "") === "after-logo" ? "after-logo" : "during-logo";
}

function normalizeCustomImages(value) {
    if (!Array.isArray(value))
        return [];
    const result = [];
    const ids = ({});
    for (let i = 0; i < value.length && result.length < 12; ++i) {
        const raw = value[i];
        if (!raw || typeof raw !== "object" || Array.isArray(raw))
            continue;
        const id = String(raw.id || "");
        const path = String(raw.path || "");
        if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]
                || !path.startsWith("/") || path.indexOf("://") >= 0)
            continue;
        const normalized = normalizedElement(raw, 0.50, 0.50, 0);
        // Custom media is not tintable. Keep its persisted schema free of the
        // generic element color field so resolver output round-trips through
        // the authoritative profile backend unchanged.
        delete normalized.color;
        normalized.id = id;
        normalized.path = path;
        normalized.spawn_animation = normalizeSpawnAnimation(raw.spawn_animation);
        normalized.spawn_timing = normalizeSpawnTiming(raw.spawn_timing);
        normalized.visible = raw.visible !== false;
        result.push(normalized);
        ids[id] = true;
    }
    return result;
}

function normalizeTimezoneClocks(value) {
    if (!Array.isArray(value))
        return [];
    const result = [];
    const ids = ({});
    for (let i = 0; i < value.length && result.length < 12; ++i) {
        const raw = value[i];
        if (!raw || typeof raw !== "object" || Array.isArray(raw))
            continue;
        let id = String(raw.id || "timezone-" + (i + 1));
        if (!/^timezone-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id])
            id = "timezone-" + (i + 1);
        const normalized = normalizedElement(raw, 0.50, 0.60 + Math.min(0.24, i * 0.04), 0);
        normalized.id = id;
        normalized.timezone = String(raw.timezone || "UTC");
        normalized.format = String(raw.format || "24h").toLowerCase() === "12h" ? "12h" : "24h";
        normalized.show_label = raw.show_label !== false;
        normalized.visible = raw.visible !== false;
        result.push(normalized);
        ids[id] = true;
    }
    return result;
}

function normalizeAlignment(value) {
    const alignment = String(value || "center");
    return alignment === "left" || alignment === "right" ? alignment : "center";
}

function normalizeVariants(value) {
    if (!Array.isArray(value))
        return [];
    const result = [];
    for (let i = 0; i < value.length && result.length < 32; ++i) {
        const variant = String(value[i] === undefined ? "" : value[i]);
        if (variant.length > 0)
            result.push(variant);
    }
    return result;
}

function normalizeCustomTexts(value) {
    if (!Array.isArray(value))
        return [];
    const result = [];
    const ids = ({});
    for (let i = 0; i < value.length && result.length < 12; ++i) {
        const raw = value[i];
        if (!raw || typeof raw !== "object" || Array.isArray(raw))
            continue;
        let id = String(raw.id || "text-" + (i + 1));
        if (!/^text-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id])
            id = "text-" + (i + 1);
        const normalized = normalizedElement(raw, 0.50, 0.55 + Math.min(0.28, i * 0.04), 0);
        normalized.id = id;
        normalized.text = String(raw.text === undefined ? "Custom Text" : raw.text);
        normalized.variants = normalizeVariants(raw.variants);
        normalized.randomize = raw.randomize === true;
        normalized.alignment = normalizeAlignment(raw.alignment);
        normalized.visible = raw.visible !== false;
        result.push(normalized);
        ids[id] = true;
    }
    return result;
}

function stableHash(value) {
    const text = String(value || "");
    let hash = 2166136261;
    for (let i = 0; i < text.length; ++i) {
        hash ^= text.charCodeAt(i);
        hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
}

function textForPresentation(item, epoch) {
    if (!item || item.randomize !== true || !Array.isArray(item.variants) || item.variants.length === 0)
        return item ? String(item.text || "") : "";
    const index = stableHash(String(item.id || "") + ":" + String(epoch || 0)) % item.variants.length;
    return String(item.variants[index]);
}


function normalizedBoolean(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function normalizedEnum(value, allowed, fallback) {
    const key = String(value === undefined || value === null ? "" : value);
    return allowed.indexOf(key) >= 0 ? key : fallback;
}

function normalizedHex(value, fallback) {
    const color = String(value === undefined || value === null ? fallback : value).toLowerCase();
    return /^#[0-9a-f]{6}$/.test(color) ? color : fallback;
}

function normalizedInteger(value, fallback, minimum, maximum) {
    const number = Math.round(Number(value));
    return Number.isFinite(number)
        ? Math.max(minimum, Math.min(maximum, number)) : fallback;
}

function normalizedWallpaperPath(value) {
    const path = typeof value === "string" ? value : "";
    if (!path.startsWith("/") || path.indexOf("://") >= 0
            || /[\u0000-\u001f\u007f-\u009f]/.test(path))
        return "";
    return path;
}

function normalizedPasswordMaskCharacter(value) {
    const text = String(value === undefined || value === null ? "" : value);
    const points = Array.from(text);
    if (points.length !== 1 || /[\u0000-\u0020\u007f-\u009f]/.test(text))
        return "•";
    return points[0];
}

function normalizedProfile(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    return ({
        lockscreen_layout: normalizeLayout(raw.lockscreen_layout),
        lockscreen_show_logo: normalizedBoolean(raw.lockscreen_show_logo, true),
        lockscreen_show_time: normalizedBoolean(raw.lockscreen_show_time, false),
        lockscreen_show_date: normalizedBoolean(raw.lockscreen_show_date, false),
        lockscreen_show_username: normalizedBoolean(raw.lockscreen_show_username, false),
        lockscreen_show_weather: normalizedBoolean(raw.lockscreen_show_weather, false),
        lockscreen_custom_images: normalizeCustomImages(raw.lockscreen_custom_images),
        lockscreen_timezone_clocks: normalizeTimezoneClocks(raw.lockscreen_timezone_clocks),
        lockscreen_custom_texts: normalizeCustomTexts(raw.lockscreen_custom_texts),
        lockscreen_visualizer: normalizeVisualizer(raw.lockscreen_visualizer),
        lockscreen_background: normalizedEnum(raw.lockscreen_background,
            ["black", "wallpaper", "color"], "black"),
        lockscreen_background_color: normalizedHex(raw.lockscreen_background_color, "#000000"),
        lockscreen_wallpaper_path: normalizedWallpaperPath(raw.lockscreen_wallpaper_path),
        lockscreen_wallpaper_fit: normalizedEnum(raw.lockscreen_wallpaper_fit,
            ["cover", "contain"], "cover"),
        lockscreen_wallpaper_focal_x: clampNumber(raw.lockscreen_wallpaper_focal_x, 0.5, 0, 1),
        lockscreen_wallpaper_focal_y: clampNumber(raw.lockscreen_wallpaper_focal_y, 0.5, 0, 1),
        lockscreen_background_opacity: normalizedInteger(raw.lockscreen_background_opacity, 100, 0, 100),
        lockscreen_background_opacity_previous: normalizedInteger(raw.lockscreen_background_opacity_previous, 100, 0, 100),
        lockscreen_overlay_mode: normalizedEnum(raw.lockscreen_overlay_mode,
            ["none", "dark", "light"], "none"),
        lockscreen_overlay_strength: normalizedInteger(raw.lockscreen_overlay_strength, 0, 0, 100),
        lockscreen_wallpaper_blur: normalizedInteger(raw.lockscreen_wallpaper_blur, 10, 0, 200),
        lockscreen_blur_style: normalizedEnum(raw.lockscreen_blur_style,
            ["smooth", "pixelated"], "pixelated"),
        lockscreen_weather_units: normalizedEnum(raw.lockscreen_weather_units,
            ["auto", "fahrenheit", "celsius"], "auto"),
        lockscreen_animation: normalizedEnum(raw.lockscreen_animation,
            ["random", "swarm", "edges", "center", "split", "off"], "split"),
        lockscreen_entry_transition: normalizedEnum(raw.lockscreen_entry_transition,
            ["fade", "pixel", "edges", "wipe"], "fade"),
        lockscreen_entry_transition_duration: normalizedInteger(raw.lockscreen_entry_transition_duration,
            1800, 800, 6000),
        lockscreen_password_mask_mode: normalizedEnum(raw.lockscreen_password_mask_mode,
            ["squares", "dots", "custom"], "squares"),
        lockscreen_password_mask_character: normalizedPasswordMaskCharacter(
            raw.lockscreen_password_mask_character),
        lockscreen_clock_format: normalizedEnum(raw.lockscreen_clock_format,
            ["24h", "12h"], "24h")
    });
}

function cloneProfile(profile) {
    return JSON.parse(JSON.stringify(normalizedProfile(profile)));
}

function sharedProfile(state) {
    return normalizedProfile(state);
}

function monitorOverrides(state) {
    const source = state && typeof state === "object" && !Array.isArray(state)
        ? state.lockscreen_monitor_overrides : null;
    if (!source || typeof source !== "object" || Array.isArray(source))
        return ({});

    const result = ({});
    const names = Object.keys(source);
    for (let i = 0; i < names.length; ++i) {
        const name = String(names[i] || "");
        const candidate = source[name];
        if (Array.from(name).length < 1 || Array.from(name).length > 128
                || /[\u0000-\u001f\u007f-\u009f]/.test(name)
                || !candidate || typeof candidate !== "object" || Array.isArray(candidate))
            continue;
        result[name] = normalizedProfile(candidate);
    }
    return result;
}

function profileForMonitor(shared, overrides, monitorName) {
    const name = String(monitorName || "");
    if (overrides && typeof overrides === "object" && !Array.isArray(overrides)
            && Object.prototype.hasOwnProperty.call(overrides, name))
        return overrides[name];
    return shared;
}
