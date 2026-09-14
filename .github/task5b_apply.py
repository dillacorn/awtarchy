from pathlib import Path


def one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


path = Path('config/quickshell/awtarchy/LockscreenEditor.qml')
s = path.read_text()

anchor = '''    function setAllDraftColors(colorValue) {'''
helpers = '''    function applyDynamicColorToAll(value) {\n        const clocks = cloneTimezoneClocks(draftTimezoneClocks);\n        const texts = cloneCustomTexts(draftCustomTexts);\n        for (const clock of clocks) clock.color = value;\n        for (const item of texts) item.color = value;\n        draftTimezoneClocks = clocks;\n        draftCustomTexts = texts;\n    }\n\n    function resetDynamicElementPosition(name) {\n        if (isTimezoneClock(name)) {\n            const next = cloneTimezoneClocks(draftTimezoneClocks);\n            const index = timezoneClockIndex(name);\n            if (index < 0) return false;\n            next[index].x = 0.5; next[index].y = 0.60; draftTimezoneClocks = next; return true;\n        }\n        if (isCustomText(name)) {\n            const next = cloneCustomTexts(draftCustomTexts);\n            const index = customTextIndex(name);\n            if (index < 0) return false;\n            next[index].x = 0.5; next[index].y = 0.55; draftCustomTexts = next; return true;\n        }\n        return false;\n    }\n\n    function resetDynamicElementToDefault(name) {\n        if (isTimezoneClock(name)) {\n            const next = cloneTimezoneClocks(draftTimezoneClocks);\n            const index = timezoneClockIndex(name);\n            if (index < 0) return false;\n            const id = next[index].id;\n            next[index] = ({ id: id, timezone: "UTC", format: "24h", x: 0.5, y: 0.60,\n                scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto", visible: true });\n            draftTimezoneClocks = next; refreshPreviewTimezoneValues(); return true;\n        }\n        if (isCustomText(name)) {\n            const next = cloneCustomTexts(draftCustomTexts);\n            const index = customTextIndex(name);\n            if (index < 0) return false;\n            const id = next[index].id;\n            next[index] = ({ id: id, text: "Custom Text", variants: [], randomize: false, alignment: "center",\n                x: 0.5, y: 0.55, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, color: "auto", visible: true });\n            draftCustomTexts = next; return true;\n        }\n        return false;\n    }\n\n    function applyDynamicSelectionVisibility(names, visible) {\n        const clocks = cloneTimezoneClocks(draftTimezoneClocks);\n        const texts = cloneCustomTexts(draftCustomTexts);\n        let clocksChanged = false; let textsChanged = false;\n        for (const name of names) {\n            if (isTimezoneClock(name)) { const index = timezoneClockIndex(name); if (index >= 0) { clocks[index].visible = !!visible; clocksChanged = true; } }\n            else if (isCustomText(name)) { const index = customTextIndex(name); if (index >= 0) { texts[index].visible = !!visible; textsChanged = true; } }\n        }\n        if (clocksChanged) draftTimezoneClocks = clocks;\n        if (textsChanged) draftCustomTexts = texts;\n    }\n\n''' + anchor
s = one(s, anchor, helpers, 'dynamic editor helper insertion')

s = one(s,
'''        nextVisualizer.color = value;\n        draftVisualizer = nextVisualizer;\n        statusMessage = value === "auto" ? "All elements use Auto contrast"''',
'''        nextVisualizer.color = value;\n        draftVisualizer = nextVisualizer;\n        applyDynamicColorToAll(value);\n        statusMessage = value === "auto" ? "All elements use Auto contrast"''',
'global dynamic colors')

s = one(s,
'''            next[index].x = 0.5;\n            next[index].y = 0.5;\n            draftCustomImages = next;\n        } else {\n            const defaults = defaultLayout();''',
'''            next[index].x = 0.5;\n            next[index].y = 0.5;\n            draftCustomImages = next;\n        } else if (resetDynamicElementPosition(name)) {\n            // Dynamic repeated elements own their reset coordinates.\n        } else {\n            const defaults = defaultLayout();''',
'dynamic position reset dispatch')

s = one(s,
'''            });\n            draftCustomImages = next;\n        } else {\n            const defaults = defaultLayout();\n            const visibility = defaultVisibility();''',
'''            });\n            draftCustomImages = next;\n        } else if (resetDynamicElementToDefault(name)) {\n            // Dynamic repeated elements preserve identity while restoring defaults.\n        } else {\n            const defaults = defaultLayout();\n            const visibility = defaultVisibility();''',
'dynamic full reset dispatch')

s = one(s,
'''        for (const name of names) { if (name === "visualizer") vz.enabled=!!visible; else if (isCustomImage(name)) { const i=ni.findIndex(image=>image.id===name); if(i>=0) ni[i].visible=!!visible; } else if (elementNames.indexOf(name)>=0) nv[name]=!!visible; }\n        nv.password=true; draftVisibility=nv; draftCustomImages=ni; draftVisualizer=vz; statusMessage=visible?"Selected elements visible":"Selected elements hidden"; scheduleContrastRefresh();''',
'''        for (const name of names) { if (name === "visualizer") vz.enabled=!!visible; else if (isCustomImage(name)) { const i=ni.findIndex(image=>image.id===name); if(i>=0) ni[i].visible=!!visible; } else if (elementNames.indexOf(name)>=0) nv[name]=!!visible; }\n        applyDynamicSelectionVisibility(names, visible);\n        nv.password=true; draftVisibility=nv; draftCustomImages=ni; draftVisualizer=vz; statusMessage=visible?"Selected elements visible":"Selected elements hidden"; scheduleContrastRefresh();''',
'dynamic multiselect visibility')

path.write_text(s)
