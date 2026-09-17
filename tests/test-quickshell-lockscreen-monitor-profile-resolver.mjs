#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const copies = [
  path.join(root, "config/quickshell/awtarchy/LockscreenPresentationState.js"),
  path.join(root, "config/quickshell/awtarchy-lock/LockscreenPresentationState.js"),
];

function loadPresentationState(file) {
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/m, "");
  const context = {};
  vm.createContext(context);
  vm.runInContext(source, context, { filename: file });
  return context;
}

for (const file of copies) {
  const api = loadPresentationState(file);
  for (const fn of [
    "sharedProfile",
    "monitorOverrides",
    "monitorProfiles",
    "lastEditedProfile",
    "migratedMonitorProfiles",
    "profileForMonitor",
    "cloneProfile",
  ])
    assert.equal(typeof api[fn], "function", `${path.basename(file)} is missing ${fn}()`);

  const shared = api.sharedProfile({
    lockscreen_background: "color",
    lockscreen_background_color: "#112233",
    lockscreen_show_time: true,
    lockscreen_layout: {
      logo: { x: 0.4, y: 0.3, scale: 1, stretch_x: 1, stretch_y: 1, opacity: 90, rotation: 12, color: "auto" },
    },
  });

  assert.equal(shared.lockscreen_background, "color");
  assert.equal(shared.lockscreen_background_color, "#112233");
  assert.equal(shared.lockscreen_show_time, true);
  assert.equal(shared.lockscreen_layout.logo.rotation, 12);
  assert.equal(shared.lockscreen_show_password, undefined, "password visibility must not become a persisted profile field");

  const legacyPassword = api.sharedProfile({
    lockscreen_layout: {
      password: {
        x: 0.94,
        y: 0.91,
        scale: 1,
        stretch_x: 1,
        stretch_y: 1,
        opacity: 5,
        rotation: 0,
        color: "auto",
      },
    },
  });
  assert.equal(legacyPassword.lockscreen_layout.password.x, 0.85,
    "resolver must clamp password x to the persistence/editor bound");
  assert.equal(legacyPassword.lockscreen_layout.password.y, 0.86,
    "resolver must clamp password y to the persistence/editor bound");
  assert.equal(legacyPassword.lockscreen_layout.password.opacity, 5,
    "resolver must clamp password opacity to the persistence/editor minimum");

  const dp1 = api.cloneProfile(shared);
  dp1.lockscreen_background_color = "#abcdef";

  const legacyState = {
    ...shared,
    lockscreen_monitor_overrides: {
      "DP-1": dp1,
      "HDMI-A-1": { lockscreen_show_time: true },
    },
  };
  const migrated = api.migratedMonitorProfiles(legacyState);
  assert.equal(migrated["DP-1"].lockscreen_background_color, "#abcdef");
  assert.equal(migrated["HDMI-A-1"].lockscreen_background, "black");
  assert.equal(migrated["HDMI-A-1"].lockscreen_show_time, true);

  const fallback = api.lastEditedProfile(legacyState);
  assert.equal(fallback.lockscreen_background_color, "#112233");
  assert.equal(
    api.profileForMonitor(migrated, fallback, "DP-1").lockscreen_background_color,
    "#abcdef",
  );
  assert.equal(
    api.profileForMonitor(migrated, fallback, "eDP-1").lockscreen_background_color,
    "#112233",
    "unseen monitors must resolve from the last-edited fallback",
  );

  const explicit = api.monitorProfiles({
    lockscreen_monitor_profiles: {
      "DP-2": dp1,
    },
    lockscreen_monitor_overrides: {
      "DP-1": { lockscreen_background_color: "#ff0000" },
    },
  });
  assert.deepEqual(Object.keys(explicit), ["DP-2"]);
  assert.deepEqual(
    Object.keys(api.migratedMonitorProfiles({
      lockscreen_monitor_profiles: {},
      lockscreen_monitor_overrides: { "DP-1": dp1 },
    })),
    [],
    "an explicit new monitor-profile map must prevent legacy overrides from remaining active",
  );

  const cloned = api.cloneProfile(shared);
  cloned.lockscreen_layout.logo.x = 0.2;
  cloned.lockscreen_custom_images.push({ id: "image-mutated" });
  assert.notEqual(cloned.lockscreen_layout.logo.x, shared.lockscreen_layout.logo.x);
  assert.equal(shared.lockscreen_custom_images.length, 0, "cloneProfile must deep-clone nested arrays");

  assert.deepEqual(
    Object.keys(shared).sort(),
    [
      "lockscreen_animation",
      "lockscreen_background",
      "lockscreen_background_color",
      "lockscreen_background_opacity",
      "lockscreen_background_opacity_previous",
      "lockscreen_blur_style",
      "lockscreen_clock_format",
      "lockscreen_custom_images",
      "lockscreen_custom_texts",
      "lockscreen_entry_transition",
      "lockscreen_entry_transition_duration",
      "lockscreen_layout",
      "lockscreen_overlay_mode",
      "lockscreen_overlay_strength",
      "lockscreen_password_mask_character",
      "lockscreen_password_mask_mode",
      "lockscreen_show_date",
      "lockscreen_show_logo",
      "lockscreen_show_time",
      "lockscreen_show_username",
      "lockscreen_show_weather",
      "lockscreen_timezone_clocks",
      "lockscreen_visualizer",
      "lockscreen_wallpaper_fit",
      "lockscreen_wallpaper_focal_x",
      "lockscreen_wallpaper_focal_y",
      "lockscreen_wallpaper_path",
      "lockscreen_wallpaper_blur",
      "lockscreen_weather_units",
    ].sort(),
    "normalized profile key set drifted",
  );
}

assert.equal(
  fs.readFileSync(copies[0], "utf8"),
  fs.readFileSync(copies[1], "utf8"),
  "unlocked and secure presentation-state helpers must remain byte-identical",
);

console.log("PASS: lockscreen monitor profile resolver contracts");
