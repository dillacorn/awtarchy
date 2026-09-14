from pathlib import Path


def one(s, old, new, label):
    if s.count(old) != 1:
        raise RuntimeError(f'{label}: expected one match, got {s.count(old)}')
    return s.replace(old, new, 1)


root = Path('.')
scene = root / 'config/quickshell/awtarchy-lock/LockScene.qml'
s = scene.read_text()
s = one(s, '    property int customImageSpawnEpoch: 0\n', '    property int customImageSpawnEpoch: 0\n    property string individualImageReplayId: ""\n    property int individualImageReplayEpoch: 0\n', 'scene replay props')
s = one(s, '    readonly property bool customImageEntryStarted:\n        presentationPhase === "custom-images" || presentationPhase === "settled"\n', '    readonly property bool customImageEntryStarted:\n        presentationPhase === "custom-images" || presentationPhase === "settled"\n    readonly property bool fullPresentationPlaybackActive:\n        effectiveEntryTransitionRunning || presentationPhase !== "settled"\n', 'scene playback state')
s = one(s, '    function customImageEntryDurationMs() {', '    function customImageEntryDurationMs(timing) {', 'duration signature')
s = one(s, '            if (!image || image.visible === false)\n                continue;', '            if (!image || image.visible === false || customImageSpawnTiming(image) !== timing)\n                continue;', 'duration timing filter')
s = one(s, '        const duration = customImageEntryDurationMs();', '        const duration = customImageEntryDurationMs("after-logo");', 'after-logo duration')
s = one(s, '    function customImageSpawnOffset(image, itemWidth, itemHeight) {', '    function customImageSpawnTiming(image) {\n        return String(image && image.spawn_timing !== undefined ? image.spawn_timing : "during-logo")\n            === "after-logo" ? "after-logo" : "during-logo";\n    }\n\n    function customImageSpawnOffset(image, itemWidth, itemHeight) {', 'timing helper')
s = one(s, '                readonly property string spawnMode: root.customImageSpawnMode(modelData)\n', '                readonly property string spawnMode: root.customImageSpawnMode(modelData)\n                readonly property string spawnTiming: root.customImageSpawnTiming(modelData)\n', 'delegate timing')
s = one(s, '                property real spawnProgress: spawnMode === "none" ? 1 : 0\n', '                property real spawnProgress: spawnMode === "none" ? 1 : 0\n                readonly property bool customImageAnimationActive: spawnAnimation.running\n                readonly property bool fullEntryStarted: spawnTiming === "during-logo"\n                    ? root.presentationPhase === "logo" || root.presentationPhase === "custom-images" || root.presentationPhase === "settled"\n                    : root.presentationPhase === "custom-images" || root.presentationPhase === "settled"\n                readonly property bool editorSettledPresentation:\n                    root.editorMode && !customImageAnimationActive && !root.fullPresentationPlaybackActive\n                readonly property real effectiveSpawnProgress: editorSettledPresentation ? 1 : spawnProgress\n', 'delegate active state')
s = one(s, '                    && (spawnMode === "none" || root.customImageEntryStarted)', '                    && (spawnMode === "none" || editorSettledPresentation || fullEntryStarted || customImageAnimationActive)', 'delegate visibility')
for old, new, label in [
    ('                x: finalX + spawnOffset.x * (1 - spawnProgress)', '                x: finalX + spawnOffset.x * (1 - effectiveSpawnProgress)', 'delegate x'),
    ('                y: finalY + spawnOffset.y * (1 - spawnProgress)', '                y: finalY + spawnOffset.y * (1 - effectiveSpawnProgress)', 'delegate y'),
    ('                scale: root.elementScale(elementName) * (spawnMode === "pixel-warp" ? 0.82 + 0.18 * spawnProgress : 1)', '                scale: root.elementScale(elementName) * (spawnMode === "pixel-warp" ? 0.82 + 0.18 * effectiveSpawnProgress : 1)', 'delegate scale'),
    ('                    * (spawnMode === "pixel-warp" ? spawnProgress : 1)', '                    * (spawnMode === "pixel-warp" ? effectiveSpawnProgress : 1)', 'delegate opacity'),
    ('customImageDelegate.spawnProgress >= 0.999', 'customImageDelegate.effectiveSpawnProgress >= 0.999', 'image smooth'),
    ('1 - customImageDelegate.spawnProgress', '1 - customImageDelegate.effectiveSpawnProgress', 'pixel factor'),
    ('customImageDelegate.spawnProgress < 0.999', 'customImageDelegate.effectiveSpawnProgress < 0.999', 'pixel visibility')
]:
    s = one(s, old, new, label)
old = '''                Connections {\n                    target: root\n                    function onPresentationPhaseChanged() {\n                        if (customImageDelegate.spawnMode !== "none"\n                                && !root.customImageEntryStarted) {\n                            spawnAnimation.stop();\n                            customImageDelegate.spawnProgress = 0;\n                        }\n                    }\n                    function onCustomImageSpawnEpochChanged() { customImageDelegate.restartSpawnAnimation(); }\n                }'''
new = '''                Connections {\n                    target: root\n                    function onPresentationPhaseChanged() {\n                        if (customImageDelegate.spawnMode === "none") { customImageDelegate.spawnProgress = 1; return; }\n                        if (root.presentationPhase === "transition") { spawnAnimation.stop(); customImageDelegate.spawnProgress = 0; }\n                    }\n                    function onLogoEntryEpochChanged() { if (customImageDelegate.spawnTiming === "during-logo") customImageDelegate.restartSpawnAnimation(); }\n                    function onCustomImageSpawnEpochChanged() { if (customImageDelegate.spawnTiming === "after-logo") customImageDelegate.restartSpawnAnimation(); }\n                    function onIndividualImageReplayEpochChanged() {\n                        if (root.editorMode && root.individualImageReplayId === customImageDelegate.elementName) customImageDelegate.restartSpawnAnimation();\n                    }\n                }'''
s = one(s, old, new, 'delegate triggers')
scene.write_text(s)
(root / 'config/quickshell/awtarchy/LockPreviewScene.qml').write_text(s)

p = root / 'config/quickshell/awtarchy/LockscreenEditor.qml'
e = p.read_text()
e = one(e, '    property int entryTransitionReplayToken: 0\n', '    property int entryTransitionReplayToken: 0\n    property string previewIndividualImageReplayId: ""\n    property int previewIndividualImageReplayEpoch: 0\n', 'editor replay props')
e = one(e, '    function normalizedLogoSpawn(value) {', '    function normalizedCustomImageSpawnTiming(value) { return String(value || "") === "after-logo" ? "after-logo" : "during-logo"; }\n\n    function normalizedLogoSpawn(value) {', 'editor timing helper')
e = one(e, '        statusMessage = "Image spawn animation updated. Use Preview Entry to preview.";', '        statusMessage = "Image spawn animation updated. Use Play Spawn to preview.";', 'editor spawn status')
anchor = '''    function beginRotateElement(name, sceneX, sceneY) {'''
insert = '''    function setDraftCustomImageSpawnTiming(name, value) {\n        const index = customImageIndex(name); if (index < 0) return;\n        const timing = normalizedCustomImageSpawnTiming(value); if (draftCustomImages[index].spawn_timing === timing) return;\n        recordUndoBeforeChange(); const next = cloneCustomImages(draftCustomImages); next[index].spawn_timing = timing; draftCustomImages = next;\n        selectElement(name, false); statusMessage = "Image spawn timing updated. Use Play Spawn to preview.";\n    }\n\n    function replaySelectedImageSpawn() {\n        if (!isCustomImage(selectedElement)) return;\n        previewIndividualImageReplayId = selectedElement;\n        previewIndividualImageReplayEpoch = previewIndividualImageReplayEpoch >= 2147483646 ? 1 : previewIndividualImageReplayEpoch + 1;\n        statusMessage = "Replaying selected image spawn";\n    }\n\n''' + anchor
e = one(e, anchor, insert, 'editor timing/replay functions')
e = one(e, 'opacity: 100, rotation: 0, spawn_animation: "none", visible: true', 'opacity: 100, rotation: 0, spawn_animation: "none", spawn_timing: "during-logo", visible: true', 'image defaults')
e = one(e, '                spawn_animation: normalizedCustomImageSpawn(raw.spawn_animation),\n                visible: typeof raw.visible === "boolean" ? raw.visible : true', '                spawn_animation: normalizedCustomImageSpawn(raw.spawn_animation),\n                spawn_timing: normalizedCustomImageSpawnTiming(raw.spawn_timing),\n                visible: typeof raw.visible === "boolean" ? raw.visible : true', 'clone timing')
old = '''                        SettingsButton { label: "Preview Entry"; textSize: 9; onClicked: root.replayEntryTransition() }\n                        Item { Layout.fillWidth: true }\n                        Text { text: "Animated images enter after the logo; No Spawn Animation remains immediate."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8; elide: Text.ElideRight }'''
new = '''                        SettingsButton { label: "During logo"; active: root.elementPoint(root.selectedElement).spawn_timing !== "after-logo"; textSize: 9; onClicked: root.setDraftCustomImageSpawnTiming(root.selectedElement, "during-logo") }\n                        SettingsButton { label: "After logo"; active: root.elementPoint(root.selectedElement).spawn_timing === "after-logo"; textSize: 9; onClicked: root.setDraftCustomImageSpawnTiming(root.selectedElement, "after-logo") }\n                        SettingsButton { label: "Play Spawn"; textSize: 9; onClicked: root.replaySelectedImageSpawn() }\n                        SettingsButton { label: "Preview Entry"; textSize: 9; onClicked: root.replayEntryTransition() }\n                        Item { Layout.fillWidth: true }\n                        Text { text: "During logo is the default; After logo waits for logo entry to finish."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8; elide: Text.ElideRight }'''
e = one(e, old, new, 'image controls')
e = one(e, '                externalEntryTransitionRunning: editorTransitionLayer.running; presentationReplayToken: root.entryTransitionReplayToken\n', '                externalEntryTransitionRunning: editorTransitionLayer.running; presentationReplayToken: root.entryTransitionReplayToken\n                individualImageReplayId: root.previewIndividualImageReplayId; individualImageReplayEpoch: root.previewIndividualImageReplayEpoch\n', 'primary replay props')
e = one(e, '                externalEntryTransitionRunning: secondaryPreviewTransitionLayer.running; presentationReplayToken: root.entryTransitionReplayToken\n', '                externalEntryTransitionRunning: secondaryPreviewTransitionLayer.running; presentationReplayToken: root.entryTransitionReplayToken\n                individualImageReplayId: root.previewIndividualImageReplayId; individualImageReplayEpoch: root.previewIndividualImageReplayEpoch\n', 'secondary replay props')
e = one(e, 'previewMode: true; editorMode: false', 'previewMode: true; editorMode: true; editorVisibility: root.draftVisibility', 'secondary settled mode')
p.write_text(e)

p = root / 'config/quickshell/awtarchy/BarState.qml'
b = p.read_text()
b = one(b, '            const spawnAnimation = lockscreenCustomImageSpawnMode(raw.spawn_animation);', '            const spawnAnimation = lockscreenCustomImageSpawnMode(raw.spawn_animation);\n            const spawnTiming = String(raw.spawn_timing || "") === "after-logo" ? "after-logo" : "during-logo";', 'BarState timing')
b = one(b, 'spawn_animation: spawnAnimation, visible: raw.visible', 'spawn_animation: spawnAnimation, spawn_timing: spawnTiming, visible: raw.visible', 'BarState timing output')
p.write_text(b)

p = root / 'config/quickshell/awtarchy-lock/shell.qml'
q = p.read_text()
q = one(q, 'import Quickshell.Wayland\n', 'import Quickshell.Wayland\nimport "../LockscreenPresentationState.js" as LockscreenPresentationState\n', 'shell shared import')
q = one(q, '            const spawnAnimation = normalizedCustomImageSpawn(image.spawn_animation);', '            const spawnAnimation = normalizedCustomImageSpawn(image.spawn_animation);\n            const spawnTiming = LockscreenPresentationState.normalizeSpawnTiming(image.spawn_timing);', 'shell timing')
q = one(q, 'rotation: rotation, spawn_animation: spawnAnimation,', 'rotation: rotation, spawn_animation: spawnAnimation, spawn_timing: spawnTiming,', 'shell timing output')
p.write_text(q)

p = root / 'tests/test-quickshell-lockscreen-presentation-sequencing.sh'
t = p.read_text()
old = '''require_text "$SCENE" 'spawnMode === "none" || root.customImageEntryStarted' \\\n    'animated custom images are not hidden until their entry phase' '''.rstrip()
new = '''require_text "$SCENE" 'function customImageSpawnTiming(image)' \\\n    'custom-image timing is not normalized in the shared scene'\nrequire_text "$SCENE" 'readonly property bool customImageAnimationActive:' \\\n    'custom-image playback is not explicitly gated by active animation'\nrequire_text "$SCENE" 'root.editorMode && !customImageAnimationActive' \\\n    'idle editor images are not forced to their settled presentation'\nrequire_text "$SCENE" 'function onLogoEntryEpochChanged()' \\\n    'during-logo custom images do not start with logo entry'\nrequire_text "$SCENE" 'function onCustomImageSpawnEpochChanged()' \\\n    'after-logo custom images do not start at the post-logo boundary' '''.rstrip()
t = one(t, old, new, 'sequencing test update')
p.write_text(t)
