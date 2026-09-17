#!/usr/bin/env python3
from pathlib import Path
import re

path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one anchor, found {text.count(old)}")
    text = text.replace(old, new, 1)


# Session profile state.
replace_once(
    '    property var draftAutoAccents: defaultAutoAccents()\n',
    '    property var draftAutoAccents: defaultAutoAccents()\n'
    '    property var draftSharedProfile: ({})\n'
    '    property var draftMonitorOverrides: ({})\n'
    '    property string activeMonitorName: ""\n'
    '    property bool profileLoadActive: false\n'
    '    property var profileUndoStacks: ({})\n'
    '    property var profileRedoStacks: ({})\n',
    'profile state properties',
)

# Profile/scalar bridge and profile-safe history.
if '    function profileFromDraftScalars() {' not in text:
    anchor = '    function editorSnapshot() {\n'
    if text.count(anchor) != 1:
        raise SystemExit('profile helper insertion anchor missing')
    block = r'''    function profileFromDraftScalars() {
        return ({
            lockscreen_layout: cloneLayout(draftLayout),
            lockscreen_show_logo: !!draftVisibility.logo,
            lockscreen_show_time: !!draftVisibility.time,
            lockscreen_show_date: !!draftVisibility.date,
            lockscreen_show_username: !!draftVisibility.username,
            lockscreen_show_weather: !!draftVisibility.weather,
            lockscreen_custom_images: cloneCustomImages(draftCustomImages),
            lockscreen_timezone_clocks: cloneTimezoneClocks(draftTimezoneClocks),
            lockscreen_custom_texts: cloneCustomTexts(draftCustomTexts),
            lockscreen_visualizer: cloneVisualizer(draftVisualizer),
            lockscreen_background: draftBackgroundMode,
            lockscreen_background_color: draftBackgroundColor,
            lockscreen_wallpaper_path: draftWallpaperPath,
            lockscreen_wallpaper_fit: draftWallpaperFit,
            lockscreen_wallpaper_focal_x: draftWallpaperFocalX,
            lockscreen_wallpaper_focal_y: draftWallpaperFocalY,
            lockscreen_background_opacity: draftBackgroundOpacity,
            lockscreen_background_opacity_previous: draftLastBackgroundOpacity,
            lockscreen_overlay_mode: draftOverlayMode,
            lockscreen_overlay_strength: draftOverlayStrength,
            lockscreen_wallpaper_blur: draftWallpaperBlur,
            lockscreen_blur_style: draftBlurStyle,
            lockscreen_weather_units: draftWeatherUnits,
            lockscreen_animation: draftLogoSpawnAnimation,
            lockscreen_entry_transition: draftEntryTransition,
            lockscreen_entry_transition_duration: draftEntryTransitionDuration,
            lockscreen_password_mask_mode: draftPasswordMaskMode,
            lockscreen_password_mask_character: draftPasswordMaskCharacter,
            lockscreen_clock_format: draftClockFormat
        });
    }

    function loadProfileIntoDraft(profile) {
        if (!profile || typeof profile !== "object")
            return;
        profileLoadActive = true;
        try {
            draftLayout = cloneLayout(profile.lockscreen_layout);
            draftCustomImages = cloneCustomImages(profile.lockscreen_custom_images);
            draftTimezoneClocks = cloneTimezoneClocks(profile.lockscreen_timezone_clocks);
            draftCustomTexts = cloneCustomTexts(profile.lockscreen_custom_texts);
            draftVisualizer = cloneVisualizer(profile.lockscreen_visualizer);
            draftVisibility = cloneVisibility(({
                logo: profile.lockscreen_show_logo,
                time: profile.lockscreen_show_time,
                date: profile.lockscreen_show_date,
                username: profile.lockscreen_show_username,
                weather: profile.lockscreen_show_weather,
                password: true
            }));
            draftBackgroundMode = String(profile.lockscreen_background || "black");
            draftBackgroundColor = String(profile.lockscreen_background_color || "#000000").toLowerCase();
            draftWallpaperPath = String(profile.lockscreen_wallpaper_path || "");
            draftWallpaperFit = String(profile.lockscreen_wallpaper_fit || "cover");
            draftWallpaperFocalX = Number(profile.lockscreen_wallpaper_focal_x);
            draftWallpaperFocalY = Number(profile.lockscreen_wallpaper_focal_y);
            draftBackgroundOpacity = Math.max(0, Math.min(100, Math.round(Number(profile.lockscreen_background_opacity))));
            draftLastBackgroundOpacity = Math.max(0, Math.min(100, Math.round(Number(profile.lockscreen_background_opacity_previous))));
            draftOverlayMode = String(profile.lockscreen_overlay_mode || "none");
            draftOverlayStrength = Math.max(0, Math.min(100, Math.round(Number(profile.lockscreen_overlay_strength))));
            draftWallpaperBlur = Math.max(0, Math.min(200, Math.round(Number(profile.lockscreen_wallpaper_blur))));
            draftBlurStyle = String(profile.lockscreen_blur_style || "pixelated");
            draftWeatherUnits = String(profile.lockscreen_weather_units || "auto");
            draftLogoSpawnAnimation = normalizedLogoSpawn(profile.lockscreen_animation);
            draftEntryTransition = String(profile.lockscreen_entry_transition || "fade");
            draftEntryTransitionDuration = Math.max(800, Math.min(6000, Math.round(Number(profile.lockscreen_entry_transition_duration))));
            draftPasswordMaskMode = normalizedPasswordMaskMode(profile.lockscreen_password_mask_mode);
            draftPasswordMaskCharacter = normalizedPasswordMaskCharacter(profile.lockscreen_password_mask_character);
            draftClockFormat = normalizedClockFormat(profile.lockscreen_clock_format);
            draftWallpaperBlurExplicit = false;
            draftAutoAccents = defaultAutoAccents();
            refreshPreviewTimezoneValues();
            if (!elementExists(selectedElement))
                selectedElement = "logo";
            selectedElements = [selectedElement];
            clearGuides();
        } finally {
            profileLoadActive = false;
        }
        scheduleContrastRefresh();
    }

    function hasIndividualConfiguration(name) {
        const key = String(name || "");
        return key.length > 0 && draftMonitorOverrides
            && typeof draftMonitorOverrides === "object"
            && Object.prototype.hasOwnProperty.call(draftMonitorOverrides, key);
    }

    function activeProfileKey() {
        return hasIndividualConfiguration(activeMonitorName)
            ? "monitor:" + activeMonitorName : "shared";
    }

    function stashHistoryForActiveProfile() {
        const key = activeProfileKey();
        const undo = Object.assign({}, profileUndoStacks);
        const redo = Object.assign({}, profileRedoStacks);
        undo[key] = cloneSnapshot(undoStack) || [];
        redo[key] = cloneSnapshot(redoStack) || [];
        profileUndoStacks = undo;
        profileRedoStacks = redo;
    }

    function restoreHistoryForActiveProfile() {
        const key = activeProfileKey();
        undoStack = cloneSnapshot(profileUndoStacks[key]) || [];
        redoStack = cloneSnapshot(profileRedoStacks[key]) || [];
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
    }

    function flushActiveProfile() {
        const profile = cloneSnapshot(profileFromDraftScalars());
        if (!profile)
            return;
        if (hasIndividualConfiguration(activeMonitorName)) {
            const next = Object.assign({}, draftMonitorOverrides);
            next[activeMonitorName] = profile;
            draftMonitorOverrides = next;
        } else {
            draftSharedProfile = profile;
        }
    }

    function effectiveProfileForMonitor(name) {
        const key = String(name || "");
        if (key === activeMonitorName)
            return profileFromDraftScalars();
        if (hasIndividualConfiguration(key))
            return cloneSnapshot(draftMonitorOverrides[key]);
        if (!hasIndividualConfiguration(activeMonitorName))
            return profileFromDraftScalars();
        return cloneSnapshot(draftSharedProfile);
    }

    function connectedScreenByName(name) {
        const key = String(name || "");
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; ++i) {
            if (screens[i] && String(screens[i].name || "") === key)
                return screens[i];
        }
        return null;
    }

    function useIndividualConfiguration() {
        if (activeMonitorName.length === 0 || hasIndividualConfiguration(activeMonitorName))
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        const next = Object.assign({}, draftMonitorOverrides);
        next[activeMonitorName] = cloneSnapshot(profileFromDraftScalars());
        draftMonitorOverrides = next;
        restoreHistoryForActiveProfile();
        statusMessage = activeMonitorName + " now uses an Individual configuration";
    }

    function useSharedConfiguration() {
        if (activeMonitorName.length === 0 || !hasIndividualConfiguration(activeMonitorName))
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        const next = Object.assign({}, draftMonitorOverrides);
        delete next[activeMonitorName];
        draftMonitorOverrides = next;
        loadProfileIntoDraft(draftSharedProfile);
        restoreHistoryForActiveProfile();
        statusMessage = activeMonitorName + " now uses Shared configuration";
    }

    function copyConfigurationTo(name) {
        const targetName = String(name || "");
        if (targetName.length === 0 || targetName === activeMonitorName || !connectedScreenByName(targetName))
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        flushActiveProfile();
        const source = cloneSnapshot(profileFromDraftScalars());
        const next = Object.assign({}, draftMonitorOverrides);
        next[targetName] = cloneSnapshot(source);
        draftMonitorOverrides = next;
        const undo = Object.assign({}, profileUndoStacks);
        const redo = Object.assign({}, profileRedoStacks);
        delete undo["monitor:" + targetName];
        delete redo["monitor:" + targetName];
        profileUndoStacks = undo;
        profileRedoStacks = redo;
        statusMessage = "Copied configuration to " + targetName;
    }

    function copyConfigurationToAllOthers() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        flushActiveProfile();
        const source = cloneSnapshot(profileFromDraftScalars());
        const next = Object.assign({}, draftMonitorOverrides);
        const undo = Object.assign({}, profileUndoStacks);
        const redo = Object.assign({}, profileRedoStacks);
        const screens = Quickshell.screens || [];
        let copied = 0;
        for (let i = 0; i < screens.length; ++i) {
            const name = screens[i] ? String(screens[i].name || "") : "";
            if (name.length === 0 || name === activeMonitorName)
                continue;
            next[name] = cloneSnapshot(source);
            delete undo["monitor:" + name];
            delete redo["monitor:" + name];
            copied++;
        }
        draftMonitorOverrides = next;
        profileUndoStacks = undo;
        profileRedoStacks = redo;
        statusMessage = copied > 0 ? "Copied configuration to all other displays" : "No other displays connected";
    }

    function switchActiveMonitor(name) {
        const target = connectedScreenByName(name);
        if (!target || String(name) === activeMonitorName)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        activeMonitorName = String(name);
        editorWindow.screen = target;
        const profile = hasIndividualConfiguration(activeMonitorName)
            ? draftMonitorOverrides[activeMonitorName] : draftSharedProfile;
        loadProfileIntoDraft(profile);
        restoreHistoryForActiveProfile();
        statusMessage = "Editing " + activeMonitorName;
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function reconcileActiveMonitor() {
        if (!open || connectedScreenByName(activeMonitorName))
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        const target = focusedScreen();
        if (!target)
            return;
        activeMonitorName = String(target.name || "");
        editorWindow.screen = target;
        const profile = hasIndividualConfiguration(activeMonitorName)
            ? draftMonitorOverrides[activeMonitorName] : draftSharedProfile;
        loadProfileIntoDraft(profile);
        restoreHistoryForActiveProfile();
        statusMessage = "Editing " + activeMonitorName;
    }

'''
    text = text.replace(anchor, block + anchor, 1)

# Replace persisted loading with a single session-level profile load.
load_pattern = re.compile(r'    function loadPersistedDraft\(\) \{.*?\n    \}\n\n    function focusedScreen\(\)', re.S)
load_replacement = r'''    function loadPersistedDraft() {
        const shared = BarState.lockscreenSharedProfile();
        const overrides = BarState.lockscreenMonitorOverrides();
        draftSharedProfile = cloneSnapshot(shared) || ({});
        draftMonitorOverrides = cloneSnapshot(overrides) || ({});
        if (activeMonitorName.length === 0 && editorWindow.screen && editorWindow.screen.name)
            activeMonitorName = String(editorWindow.screen.name);
        const profile = hasIndividualConfiguration(activeMonitorName)
            ? draftMonitorOverrides[activeMonitorName] : draftSharedProfile;
        loadProfileIntoDraft(profile);
        profileUndoStacks = ({});
        profileRedoStacks = ({});
        undoStack = [];
        redoStack = [];
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        statusMessage = "";
    }

    function focusedScreen()'''
text, count = load_pattern.subn(load_replacement, text, count=1)
if count != 1 and 'const shared = BarState.lockscreenSharedProfile();' not in text:
    raise SystemExit('loadPersistedDraft replacement failed')

# Opening establishes the active target before loading persisted state once.
open_pattern = re.compile(r'    function openForScreen\(target\) \{.*?\n    \}\n    function openFocused\(\)', re.S)
open_replacement = r'''    function openForScreen(target) {
        elementOpacityBeforeOpaque = ({});
        if (target)
            editorWindow.screen = target;
        activeMonitorName = target && target.name
            ? String(target.name) : (editorWindow.screen && editorWindow.screen.name ? String(editorWindow.screen.name) : "");
        loadPersistedDraft();
        settingsBarOffsetY = 0; undoStack = []; redoStack = []; historyTransactionActive = false; historyTransactionSnapshot = null; inertiaOwner = ""; activeDrawer = ""; pickerSuspended = false;
        editingActive = true; previewCaptureDirectory = ""; previewCapturePendingDirectory = ""; editorEntranceOpacity = 0; editorWindow.visible = false; statusMessage = "Capturing current desktop preview…"; previewCaptureDelay.restart();
    }
    function openFocused()'''
text, count = open_pattern.subn(open_replacement, text, count=1)
if count != 1 and 'activeMonitorName = target && target.name' not in text:
    raise SystemExit('openForScreen replacement failed')

# Cancel/close writes nothing; next open performs the persisted reload.
text = text.replace(
    'editorWindow.visible = false; cleanupPreviewCaptureDirectory(capturedPreview); loadPersistedDraft();',
    'editorWindow.visible = false; cleanupPreviewCaptureDirectory(capturedPreview);',
    1,
)

# Atomic Shared + override save.
save_pattern = re.compile(r'    function save\(\) \{.*?\n    \}\n\n    function elementLabel', re.S)
save_replacement = r'''    function save() {
        if (saveProcess.running || contrastPersistProcess.running)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        saveErrorMessage = "";
        statusMessage = "Saving…";
        saveProcess.exec(["bash", editorSaveBackend, "--profiles",
            JSON.stringify(draftSharedProfile), JSON.stringify(draftMonitorOverrides)]);
    }

    function elementLabel'''
text, count = save_pattern.subn(save_replacement, text, count=1)
if count != 1 and 'JSON.stringify(draftMonitorOverrides)' not in text:
    raise SystemExit('save replacement failed')

# Screen topology changes keep disconnected overrides and only retarget the active editor.
if 'function onScreensChanged()' not in text:
    anchor = '    PanelWindow {\n        id: editorWindow\n'
    if text.count(anchor) != 1:
        raise SystemExit('topology connection anchor missing')
    connection = '''    Connections {\n        target: Quickshell\n        function onScreensChanged() {\n            if (root.open)\n                Qt.callLater(() => root.reconcileActiveMonitor());\n        }\n    }\n\n'''
    text = text.replace(anchor, connection + anchor, 1)

# Monitor selector/mode/copy controls live only in the active editor window.
if 'text: "Copy Configuration To"' not in text:
    anchor = '                    id: editorDockContent; anchors.fill: parent; anchors.margins: 9; spacing: 6\n'
    if text.count(anchor) != 1:
        raise SystemExit('editor controls anchor missing')
    controls = r'''                    RowLayout {
                        Layout.fillWidth: true; spacing: 7
                        Text { text: "Display"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Repeater {
                            model: Quickshell.screens
                            SettingsButton { required property var modelData; label: String(modelData.name); active: root.activeMonitorName === String(modelData.name); textSize: 9; onClicked: root.switchActiveMonitor(String(modelData.name)) }
                        }
                        Text { text: root.hasIndividualConfiguration(root.activeMonitorName) ? "Individual" : "Shared"; color: root.hasIndividualConfiguration(root.activeMonitorName) ? Theme.focus : Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true }
                        SettingsButton { label: root.hasIndividualConfiguration(root.activeMonitorName) ? "Use Shared Configuration" : "Use Individual Configuration"; textSize: 9; onClicked: { if (root.hasIndividualConfiguration(root.activeMonitorName)) root.useSharedConfiguration(); else root.useIndividualConfiguration(); } }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 7
                        Text { text: "Copy Configuration To"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Repeater {
                            model: Quickshell.screens
                            SettingsButton { required property var modelData; visible: String(modelData.name) !== root.activeMonitorName; label: String(modelData.name); textSize: 9; onClicked: root.copyConfigurationTo(String(modelData.name)) }
                        }
                        SettingsButton { label: "All Other Displays"; textSize: 9; available: (Quickshell.screens || []).length > 1; onClicked: root.copyConfigurationToAllOthers() }
                        Item { Layout.fillWidth: true }
                    }
'''
    text = text.replace(anchor, anchor + controls, 1)

# Passive preview surfaces resolve their own complete profile.
replace_once(
    '            id: secondaryPreviewWindow; required property var modelData; screen: modelData; visible:',
    '            id: secondaryPreviewWindow; required property var modelData; readonly property var monitorProfile: root.effectiveProfileForMonitor(modelData.name); screen: modelData; visible:',
    'secondary monitor profile',
)

if 'id: secondaryWallpaperState' not in text:
    anchor = '            LockPreviewScene { id: secondaryPreviewScene;'
    if text.count(anchor) != 1:
        raise SystemExit('secondary wallpaper anchor missing')
    text = text.replace(anchor,
        '            LockPreviewWallpaperState { id: secondaryWallpaperState; path: secondaryPreviewWindow.monitorProfile.lockscreen_wallpaper_path }\n'
        + anchor, 1)

secondary_pattern = re.compile(
    r'            LockPreviewScene \{ id: secondaryPreviewScene;.*?\n            \}\n            LockPreviewTransitionLayer \{ id: secondaryPreviewTransitionLayer;.*?\n            \}',
    re.S,
)
secondary_replacement = r'''            LockPreviewScene { id: secondaryPreviewScene; parent: secondaryPreviewContent; anchors.fill: parent; theme: Theme; animationPreference: secondaryPreviewWindow.monitorProfile.lockscreen_animation
                externalEntryTransitionRunning: secondaryPreviewTransitionLayer.running; presentationReplayToken: root.entryTransitionReplayToken
                individualImageReplayId: root.previewIndividualImageReplayId; individualImageReplayEpoch: root.previewIndividualImageReplayEpoch
                randomFormationMode: 3; logoPhysicsHz: BarState.lockscreenLogoPhysicsHz(); mouseInteractive: false
                showLogo: secondaryPreviewWindow.monitorProfile.lockscreen_show_logo; showTime: secondaryPreviewWindow.monitorProfile.lockscreen_show_time; showDate: secondaryPreviewWindow.monitorProfile.lockscreen_show_date; showUsername: secondaryPreviewWindow.monitorProfile.lockscreen_show_username; showWeather: secondaryPreviewWindow.monitorProfile.lockscreen_show_weather
                weatherText: secondaryPreviewWindow.monitorProfile.lockscreen_weather_units === "celsius" ? "22°C · Clear" : "72°F · Clear"
                backgroundMode: secondaryPreviewWindow.monitorProfile.lockscreen_background; wallpaperSource: secondaryWallpaperState.source; backgroundColor: secondaryPreviewWindow.monitorProfile.lockscreen_background_color
                wallpaperFit: secondaryPreviewWindow.monitorProfile.lockscreen_wallpaper_fit; wallpaperFocalX: secondaryPreviewWindow.monitorProfile.lockscreen_wallpaper_focal_x; wallpaperFocalY: secondaryPreviewWindow.monitorProfile.lockscreen_wallpaper_focal_y
                overlayMode: secondaryPreviewWindow.monitorProfile.lockscreen_overlay_mode; overlayStrength: secondaryPreviewWindow.monitorProfile.lockscreen_overlay_strength; wallpaperBlur: secondaryPreviewWindow.monitorProfile.lockscreen_wallpaper_blur; blurStyle: secondaryPreviewWindow.monitorProfile.lockscreen_blur_style
                autoAccents: root.draftAutoAccents; layout: secondaryPreviewWindow.monitorProfile.lockscreen_layout; customImages: secondaryPreviewWindow.monitorProfile.lockscreen_custom_images; timezoneClocks: secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks; timezoneValues: ({}); customTexts: secondaryPreviewWindow.monitorProfile.lockscreen_custom_texts
                visualizer: secondaryPreviewWindow.monitorProfile.lockscreen_visualizer; audioBands: previewAudioAnalyzer.bands; backgroundOpacity: secondaryPreviewWindow.monitorProfile.lockscreen_background_opacity
                passwordMaskMode: secondaryPreviewWindow.monitorProfile.lockscreen_password_mask_mode; passwordMaskCharacter: secondaryPreviewWindow.monitorProfile.lockscreen_password_mask_character; clockFormat: secondaryPreviewWindow.monitorProfile.lockscreen_clock_format
                desktopBackingSource: secondaryTransitionStart; previewMode: true; editorMode: true; editorVisibility: ({ logo: secondaryPreviewWindow.monitorProfile.lockscreen_show_logo, time: secondaryPreviewWindow.monitorProfile.lockscreen_show_time, date: secondaryPreviewWindow.monitorProfile.lockscreen_show_date, username: secondaryPreviewWindow.monitorProfile.lockscreen_show_username, weather: secondaryPreviewWindow.monitorProfile.lockscreen_show_weather, password: true })
            }
            LockPreviewTransitionLayer { id: secondaryPreviewTransitionLayer; parent: secondaryPreviewContent; anchors.fill: parent; z: 160; startSource: secondaryTransitionStart; endSource: secondaryPreviewScene; mode: secondaryPreviewWindow.monitorProfile.lockscreen_entry_transition; duration: secondaryPreviewWindow.monitorProfile.lockscreen_entry_transition_duration; replayToken: root.entryTransitionReplayToken; autoStart: false }
'''
text, count = secondary_pattern.subn(secondary_replacement, text, count=1)
if count != 1 and 'mode: secondaryPreviewWindow.monitorProfile.lockscreen_entry_transition' not in text:
    raise SystemExit('secondary preview profile replacement failed')

# Simple structural sanity check before CI runs the permanent contracts.
if text.count('{') != text.count('}'):
    raise SystemExit(f'LockscreenEditor brace imbalance after Task 4 patch: {text.count("{")} != {text.count("}")}')

path.write_text(text, encoding="utf-8")
