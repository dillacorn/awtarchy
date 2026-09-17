#!/usr/bin/env python3
from pathlib import Path

path = Path("config/quickshell/awtarchy/LockscreenWeather.qml")
text = path.read_text(encoding="utf-8")
old = '''        function addProfile(profile) {
            if (!profile || typeof profile !== "object" || profile.lockscreen_show_weather !== true)
                return;
            const mode = root.normalizedUnitMode(profile.lockscreen_weather_units);
            if (seen[mode])
                return;
            seen[mode] = true;
            modes.push(mode);
        }
'''
new = '''        function addProfile(profile) {
            if (!profile || typeof profile !== "object")
                return;
            if (profile.lockscreen_show_weather === true) {
                const mode = root.normalizedUnitMode(profile.lockscreen_weather_units);
                if (seen[mode])
                    return;
                seen[mode] = true;
                modes.push(mode);
            }
        }
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 6 explicit weather visibility anchor missing")
path.write_text(text, encoding="utf-8")
