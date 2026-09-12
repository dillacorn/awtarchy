from pathlib import Path
import hashlib, re
R = Path.cwd()

def p(path): return R / path
def get(path): return p(path).read_text()
def put(path, text): p(path).write_text(text)
def one(text, old, new, label):
    n=text.count(old)
    if n != 1: raise RuntimeError(f'{label}: expected 1, got {n}')
    return text.replace(old,new,1)
def rx(text, pattern, repl, label, flags=re.S):
    out,n=re.subn(pattern,repl,text,count=1,flags=flags)
    if n != 1: raise RuntimeError(f'{label}: expected 1, got {n}')
    return out

# LockSurface: password is immediately available above transition; failure masks persist red.
f='config/quickshell/awtarchy-lock/LockSurface.qml'; s=get(f)
s=one(s,'    readonly property int maskedCount: Math.min(password.text.length, 10)\n','    readonly property int maskedCount: root.passwordFailureMaskCount > 0\n        ? root.passwordFailureMaskCount : Math.min(password.text.length, 10)\n','masked')
s=one(s,'    property bool entered: false\n','    property bool entered: false\n    property int submittedMaskCount: 0\n    property int passwordFailureMaskCount: 0\n','failure props')
s=one(s,'        const response = password.text;\n        if (auth.submit(response))\n            password.text = "";\n','        const response = password.text;\n        root.submittedMaskCount = Math.min(response.length, 10);\n        root.passwordFailureMaskCount = 0;\n        if (auth.submit(response))\n            password.text = "";\n','submit')
s=rx(s,r'    function focusPasswordWhenReady\(\) \{.*?\n    \}\n','    function focusPasswordWhenReady() {\n        Qt.callLater(() => password.forceActiveFocus());\n    }\n','focus')
s=one(s,'                visible: status === Image.Ready\n','                visible: status === Image.Ready\n                    && (!root.transitionComplete || root.wallpaperBlur <= 0)\n','desktop source hide')
s=one(s,'        z: 20\n        opacity: scene.securePasswordEntryOpacity * scene.elementOpacity("password")\n            * (root.transitionComplete ? 1 : 0)\n','        z: 1100\n        opacity: scene.securePasswordEntryOpacity * scene.elementOpacity("password")\n','password layer')
s=rx(s,r'\n        Rectangle \{\n            anchors\.centerIn: parent\n            width: root\.maskSpread\n            height: Math\.round\(14 \* root\.uiScale \* root\.passwordScale\)\n            color: scene\.elementColor\("password"\)\n            opacity: password\.text\.length > 0 \? 0\.09 : 0\n        \}\n','\n','password panel')
s=one(s,'                    color: scene.elementColor("password")\n                    opacity: 0.82\n','                    color: root.auth.statusIsError || root.passwordFailureMaskCount > 0\n                        ? "#ff4d4d" : scene.elementColor("password")\n                    opacity: 0.82\n','red masks')
s=rx(s,r'            onTextChanged: \{.*?\n            \}\n\n            Keys\.onReturnPressed','            onTextChanged: {\n                if (text.length > 0) {\n                    root.passwordFailureMaskCount = 0;\n                    if (root.auth.statusIsError)\n                        root.auth.clearStatus();\n                }\n            }\n\n            Keys.onReturnPressed','recover')
s=one(s,'        function onAuthenticationFailed() {\n            password.text = "";\n            root.focusPasswordWhenReady();\n        }\n','        function onAuthenticationFailed() {\n            root.passwordFailureMaskCount = Math.max(1, root.submittedMaskCount);\n            password.text = "";\n            root.focusPasswordWhenReady();\n        }\n','failure')
s=one(s,'    Component.onCompleted: root.entered = true\n','    Component.onCompleted: {\n        root.entered = true;\n        root.focusPasswordWhenReady();\n    }\n','initial focus')
put(f,s)

# Shared transition renderer. Pixel block is deliberately untouched.
f='config/quickshell/awtarchy-lock/LockTransitionLayer.qml'; s=get(f)
s=rx(s,r'    // Edges reveals.*?\n    Item \{\n        id: edgesClip.*?\n    \}\n\n    // Reverse Iris', '''    // Edges reveals the lockscreen from the left/right edges only.
    Item {
        id: edgesClip
        z: 2
        width: Math.max(0, root.width * (1 - root.progress))
        height: root.height
        x: (root.width - width) / 2
        y: 0
        clip: true
        visible: root.running && root.normalizedMode === "edges"

        ShaderEffectSource {
            x: -edgesClip.x
            y: 0
            width: root.width
            height: root.height
            sourceItem: root.startSource
            live: true
            recursive: false
            smooth: true
        }
    }

    // Reverse Iris''','edges')
s=rx(s,r'    // Reverse Iris.*?\n    MultiEffect \{\n        id: irisStartEffect.*?\n    \}\n\n    NumberAnimation', '''    // Reverse Iris keeps the frozen desktop as the base and directly
    // reveals the real lockscreen destination through an expanding mask.
    ShaderEffectSource {
        id: irisStartSource
        anchors.fill: parent
        z: 2
        sourceItem: root.startSource
        live: true
        recursive: false
        smooth: true
        visible: root.running && root.normalizedMode === "iris"
    }

    Item {
        id: irisMaskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            anchors.centerIn: parent
            width: root.irisDiameter
            height: width
            radius: width / 2
            color: "#ffffff"
        }
    }

    MultiEffect {
        id: irisEndEffect
        anchors.fill: parent
        z: 3
        source: root.endSource
        autoPaddingEnabled: false
        maskEnabled: true
        maskInverted: false
        maskSource: irisMaskShape
        maskSpreadAtMin: 0.015
        maskSpreadAtMax: 0.015
        visible: root.running && root.normalizedMode === "iris"
    }

    NumberAnimation''','iris')
put(f,s); put('config/quickshell/awtarchy/LockPreviewTransitionLayer.qml',s)

# Scene: immediate secure password presentation, real wallpaper blur, LR-only fallback edges.
f='config/quickshell/awtarchy-lock/LockScene.qml'; s=get(f)
s=rx(s,r'    readonly property real securePasswordEntryOpacity:.*?\n(?=    readonly property|    property|    signal|    function)','    readonly property real securePasswordEntryOpacity: root.unlocking\n        ? 0 : root.entered ? 1 : 0\n','scene password')
s=one(s,'            visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0\n            source: root.wallpaperSource\n','            visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0\n                && root.wallpaperBlur <= 0\n            source: root.wallpaperSource\n','wallpaper visibility')
anchor='''        Image {
            id: wallpaperImage
            visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
                && root.wallpaperBlur <= 0
            source: root.wallpaperSource
            asynchronous: false
            cache: false
            fillMode: Image.Stretch
            x: root.wallpaperGeometry().x
            y: root.wallpaperGeometry().y
            width: root.wallpaperGeometry().width
            height: root.wallpaperGeometry().height
            smooth: true
        }
'''
effect=anchor+'''
        MultiEffect {
            id: wallpaperBlurEffect
            x: wallpaperImage.x
            y: wallpaperImage.y
            width: wallpaperImage.width
            height: wallpaperImage.height
            source: wallpaperImage
            autoPaddingEnabled: false
            blurEnabled: root.wallpaperBlur > 0
            blurMax: 32
            blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))
            visible: root.backgroundMode === "wallpaper"
                && root.wallpaperSource.length > 0
                && root.wallpaperBlur > 0
                && wallpaperImage.status === Image.Ready
        }
'''
s=one(s,anchor,effect,'wallpaper effect')
s=rx(s,r'\n            Rectangle \{\n                anchors\.centerIn: parent\n                width: Math\.round\(80 \* root\.uiScale \* root\.elementScale\("password"\)\).*?\n            \}\n','\n','preview password panel')
s=rx(s,r'        Rectangle \{\n            visible: root\.entryTransitionMode\(\) === "edges"\n            anchors\.top: parent\.top.*?\n        \}\n        Rectangle \{\n            visible: root\.entryTransitionMode\(\) === "edges"\n            anchors\.bottom: parent\.bottom.*?\n        \}\n','','vertical fallback edges')
put(f,s); put('config/quickshell/awtarchy/LockPreviewScene.qml',s)

# State persistence: last non-opaque metadata stays alongside authoritative opacity.
f='config/hypr/scripts/quickshell_application_state.sh'; s=get(f)
s=one(s,'        lockscreen_wallpaper_blur: 0\n','        lockscreen_wallpaper_blur: 0,\n        lockscreen_background_opacity_previous: 100\n','state default')
s=rx(s,r'    jq --argjson value "\$value" \'\.lockscreen_background_opacity = \$value\' \\\n        "\$STATE_FILE" >"\$TMP_FILE"','''    jq --argjson value "$value" '
        if $value < 100 then .lockscreen_background_opacity_previous = $value else . end
        | .lockscreen_background_opacity = $value
    ' "$STATE_FILE" >"$TMP_FILE"''','state setter')
s=one(s,'    local entry_transition_duration_input="${17:-1800}"\n    local custom_images visualizer background_opacity entry_transition entry_transition_duration\n','    local entry_transition_duration_input="${17:-1800}"\n    local background_opacity_previous_input="${18:-100}"\n    local custom_images visualizer background_opacity background_opacity_previous entry_transition entry_transition_duration\n','state arg')
s=one(s,'    background_opacity="$(normalize_percent_integer "$background_opacity_input" \'lockscreen background opacity\')"\n    validate_int_range "$entry_transition_duration_input" 800 6000 \'lockscreen entry transition duration\'\n','    background_opacity="$(normalize_percent_integer "$background_opacity_input" \'lockscreen background opacity\')"\n    background_opacity_previous="$(normalize_percent_integer "$background_opacity_previous_input" \'lockscreen previous background opacity\')"\n    validate_int_range "$entry_transition_duration_input" 800 6000 \'lockscreen entry transition duration\'\n','state normalize')
s=one(s,'        --argjson background_opacity "$background_opacity" \\\n        --arg entry_transition "$entry_transition" \\\n','        --argjson background_opacity "$background_opacity" \\\n        --argjson background_opacity_previous "$background_opacity_previous" \\\n        --arg entry_transition "$entry_transition" \\\n','state jq arg')
s=one(s,'        | .lockscreen_background_opacity = $background_opacity\n        | .lockscreen_entry_transition = $entry_transition\n','        | .lockscreen_background_opacity = $background_opacity\n        | .lockscreen_background_opacity_previous = $background_opacity_previous\n        | .lockscreen_entry_transition = $entry_transition\n','state save')
s=one(s,'        | .lockscreen_background_opacity = 100\n','        | .lockscreen_background_opacity = 100\n        | .lockscreen_background_opacity_previous = 100\n','state reset')
put(f,s)

# BarState reads last non-opaque metadata.
f='config/quickshell/awtarchy/BarState.qml'; s=get(f)
s=one(s,'        lockscreen_wallpaper_blur: 0\n','        lockscreen_wallpaper_blur: 0,\n        lockscreen_background_opacity_previous: 100\n','bar default')
needle='''    function lockscreenBackgroundOpacity() {
        const value = Number(data().lockscreen_background_opacity);
        if (!Number.isFinite(value) || !Number.isInteger(value) || value < 0 || value > 100)
            return 100;
        return value;
    }
'''
s=one(s,needle,needle+'''
    function lockscreenPreviousBackgroundOpacity() {
        const value = Number(data().lockscreen_background_opacity_previous);
        if (Number.isFinite(value) && Number.isInteger(value) && value >= 0 && value < 100)
            return value;
        const current = lockscreenBackgroundOpacity();
        return current < 100 ? current : 100;
    }
''','bar getter')
put(f,s)

# Editor state and transforms.
f='config/quickshell/awtarchy/LockscreenEditor.qml'; s=get(f)
s=one(s,'    property int draftBackgroundOpacity: 100\n','    property int draftBackgroundOpacity: 100\n    property int draftLastBackgroundOpacity: 100\n','draft previous')
s=one(s,'    property real resizeCenterY: 0\n','    property real resizeCenterY: 0\n    property var resizeGroupSnapshot: []\n    property real resizeGroupCenterX: 0\n    property real resizeGroupCenterY: 0\n    property real resizeGroupCenterNormalizedX: 0\n    property real resizeGroupCenterNormalizedY: 0\n','group props')
s=one(s,'            backgroundOpacity: draftBackgroundOpacity,\n','            backgroundOpacity: draftBackgroundOpacity,\n            lastBackgroundOpacity: draftLastBackgroundOpacity,\n','snapshot')
s=one(s,'        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)\n            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;\n        const entryTransition = String(snapshot.entryTransition || "fade");\n','        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)\n            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;\n        const lastBackgroundOpacity = Number(snapshot.lastBackgroundOpacity);\n        draftLastBackgroundOpacity = Number.isFinite(lastBackgroundOpacity)\n            ? Math.max(0, Math.min(100, Math.round(lastBackgroundOpacity)))\n            : (draftBackgroundOpacity < 100 ? draftBackgroundOpacity : 100);\n        const entryTransition = String(snapshot.entryTransition || "fade");\n','restore previous')
s=one(s,'        draftEntryTransitionDuration = Number.isFinite(transitionDuration)\n            ? Math.max(400, Math.min(4000, transitionDuration)) : 1200;\n','        draftEntryTransitionDuration = Number.isFinite(transitionDuration)\n            ? Math.max(800, Math.min(6000, transitionDuration)) : 1800;\n','restore duration')
s=one(s,'    function primaryPoint() {\n','    function selectAllElements() {\n        const names = editableElementNames().filter(name => elementExists(name));\n        if (names.length === 0) return;\n        selectedElements = names;\n        if (names.indexOf(selectedElement) < 0) selectedElement = names[0];\n        statusMessage = "Selected all editable elements";\n    }\n\n    function primaryPoint() {\n','select all')
s=one(s,'        if (!Number.isFinite(numeric) || numeric < -180 || numeric > 180) {\n            statusMessage = "Rotation must be -180 to 180 degrees";\n','        if (!Number.isFinite(numeric)) {\n            statusMessage = "Rotation must be a number";\n','rotation input')
s=one(s,'                rotation: Math.max(-180, Math.min(180, Number.isFinite(rotation) ? rotation : 0)),\n','                rotation: normalizedRotation(Number.isFinite(rotation) ? rotation : 0),\n','rotation clone')
s=rx(s,r'    function beginResizeElement\(name, sceneX, sceneY\) \{.*?\n    function setDraftVisualizerWidth',r'''    function beginGroupResize(sceneX, sceneY) {
        const names = selectedElements.filter(name => elementExists(name));
        if (names.length <= 1 || editorFocus.width <= 0 || editorFocus.height <= 0) return false;
        let minX=1, maxX=0, minY=1, maxY=0;
        const snapshot=[];
        for (const name of names) {
            const point=elementPoint(name); if (!point) continue;
            const hw=Math.max(0,Number(previewScene.elementVisualWidth(name)))/Math.max(1,editorFocus.width)/2;
            const hh=Math.max(0,Number(previewScene.elementVisualHeight(name)))/Math.max(1,editorFocus.height)/2;
            minX=Math.min(minX,Number(point.x)-hw); maxX=Math.max(maxX,Number(point.x)+hw);
            minY=Math.min(minY,Number(point.y)-hh); maxY=Math.max(maxY,Number(point.y)+hh);
            snapshot.push(({name:name,x:Number(point.x),y:Number(point.y),scale:elementScale(name)}));
        }
        if (snapshot.length <= 1) return false;
        resizeGroupCenterNormalizedX=(minX+maxX)/2; resizeGroupCenterNormalizedY=(minY+maxY)/2;
        resizeGroupCenterX=resizeGroupCenterNormalizedX*editorFocus.width;
        resizeGroupCenterY=resizeGroupCenterNormalizedY*editorFocus.height;
        resizeStartDistance=Math.max(12,Math.sqrt(Math.pow(Number(sceneX)-resizeGroupCenterX,2)+Math.pow(Number(sceneY)-resizeGroupCenterY,2)));
        resizeGroupSnapshot=snapshot; resizeElementName=selectedElement; beginHistoryTransaction(); return true;
    }

    function clampedGroupScaleFactor(requestedFactor) {
        let maximum=Number.POSITIVE_INFINITY, minimum=0;
        for (const item of resizeGroupSnapshot) {
            const scale=Math.max(0.0001,Number(item.scale));
            minimum=Math.max(minimum,0.50/scale); maximum=Math.min(maximum,elementScaleMaximum/scale);
            const b=pointBounds(item.name), dx=Number(item.x)-resizeGroupCenterNormalizedX, dy=Number(item.y)-resizeGroupCenterNormalizedY;
            if (dx>0) maximum=Math.min(maximum,(b.maxX-resizeGroupCenterNormalizedX)/dx);
            else if (dx<0) maximum=Math.min(maximum,(b.minX-resizeGroupCenterNormalizedX)/dx);
            if (dy>0) maximum=Math.min(maximum,(b.maxY-resizeGroupCenterNormalizedY)/dy);
            else if (dy<0) maximum=Math.min(maximum,(b.minY-resizeGroupCenterNormalizedY)/dy);
        }
        const hi=Number.isFinite(maximum)?Math.max(minimum,maximum):elementScaleMaximum;
        return Math.max(minimum,Math.min(hi,Number(requestedFactor)||1));
    }

    function updateGroupResize(sceneX, sceneY) {
        if (resizeGroupSnapshot.length <= 1) return;
        const distance=Math.max(1,Math.sqrt(Math.pow(Number(sceneX)-resizeGroupCenterX,2)+Math.pow(Number(sceneY)-resizeGroupCenterY,2)));
        const factor=clampedGroupScaleFactor(distance/resizeStartDistance);
        const nl=cloneLayout(draftLayout), ni=cloneCustomImages(draftCustomImages), nv=cloneVisualizer(draftVisualizer);
        for (const item of resizeGroupSnapshot) {
            const x=resizeGroupCenterNormalizedX+(Number(item.x)-resizeGroupCenterNormalizedX)*factor;
            const y=resizeGroupCenterNormalizedY+(Number(item.y)-resizeGroupCenterNormalizedY)*factor;
            const scale=Math.max(0.50,Math.min(elementScaleMaximum,Number(item.scale)*factor));
            if (item.name === "visualizer") { nv.x=x; nv.y=y; nv.scale=scale; }
            else if (isCustomImage(item.name)) { const i=ni.findIndex(image=>image.id===item.name); if(i>=0){ni[i].x=x;ni[i].y=y;ni[i].scale=scale;} }
            else if (elementNames.indexOf(item.name)>=0) { nl[item.name].x=x; nl[item.name].y=y; nl[item.name].scale=scale; }
        }
        draftLayout=nl; draftCustomImages=ni; draftVisualizer=nv; scheduleContrastRefresh();
    }

    function beginResizeElement(name, sceneX, sceneY) {
        if (!elementExists(name) || editorFocus.width<=0 || editorFocus.height<=0) return;
        if (selectedContains(name) && selectedElements.length>1 && beginGroupResize(sceneX,sceneY)) return;
        selectElement(name,false); resizeGroupSnapshot=[];
        const point=elementPoint(name); resizeElementName=name;
        resizeCenterX=Number(point.x)*editorFocus.width; resizeCenterY=Number(point.y)*editorFocus.height;
        resizeStartDistance=Math.max(12,Math.sqrt(Math.pow(Number(sceneX)-resizeCenterX,2)+Math.pow(Number(sceneY)-resizeCenterY,2)));
        resizeStartScale=elementScale(name); beginHistoryTransaction();
    }

    function updateResizeElement(sceneX, sceneY) {
        if (resizeElementName.length===0) return;
        if (resizeGroupSnapshot.length>1) { updateGroupResize(sceneX,sceneY); return; }
        const distance=Math.max(1,Math.sqrt(Math.pow(Number(sceneX)-resizeCenterX,2)+Math.pow(Number(sceneY)-resizeCenterY,2)));
        setDraftScaleSilently(resizeElementName,resizeStartScale*distance/resizeStartDistance);
    }

    function endResizeElement() {
        if (resizeElementName.length===0) return;
        resizeElementName=""; resizeGroupSnapshot=[]; commitHistoryTransaction();
    }

    function setDraftVisualizerWidth''','group scale')
marker='''    function elementEnabled(name) {
'''
groupvis='''    function selectionAllVisible() {
        const names=selectedElements.filter(name => name !== "password" && elementCanHide(name));
        return names.length===0 || names.every(name => elementEnabled(name));
    }

    function setSelectedVisibility(visible) {
        const names=selectedElements.filter(name => name !== "password" && elementCanHide(name));
        if (names.length===0) return;
        recordUndoBeforeChange();
        const nv=cloneVisibility(draftVisibility), ni=cloneCustomImages(draftCustomImages), vz=cloneVisualizer(draftVisualizer);
        for (const name of names) {
            if (name === "visualizer") vz.enabled=!!visible;
            else if (isCustomImage(name)) { const i=ni.findIndex(image=>image.id===name); if(i>=0) ni[i].visible=!!visible; }
            else if (elementNames.indexOf(name)>=0) nv[name]=!!visible;
        }
        nv.password=true; draftVisibility=nv; draftCustomImages=ni; draftVisualizer=vz;
        statusMessage=visible?"Selected elements visible":"Selected elements hidden"; scheduleContrastRefresh();
    }

'''
s=one(s,marker,groupvis+marker,'group visibility')
s=one(s,'        if (draftBackgroundOpacity === 100 && next < 100 && draftWallpaperBlur === 0\n                && !draftWallpaperBlurExplicit)\n            draftWallpaperBlur = 20;\n        draftBackgroundOpacity = next;\n    }\n','        if (draftBackgroundOpacity === 100 && next < 100 && draftWallpaperBlur === 0\n                && !draftWallpaperBlurExplicit)\n            draftWallpaperBlur = 20;\n        if (next < 100) draftLastBackgroundOpacity = next;\n        draftBackgroundOpacity = next;\n    }\n\n    function toggleBackgroundOpaque() {\n        if (draftBackgroundOpacity < 100) {\n            draftLastBackgroundOpacity = draftBackgroundOpacity;\n            setDraftBackgroundOpacity(100);\n        } else if (draftLastBackgroundOpacity < 100) {\n            setDraftBackgroundOpacity(draftLastBackgroundOpacity);\n        }\n    }\n','opaque')
s=one(s,'        draftBackgroundOpacity = 100;\n','        draftBackgroundOpacity = 100;\n        draftLastBackgroundOpacity = 100;\n','reset opacity')
s=one(s,'        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();\n','        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();\n        draftLastBackgroundOpacity = BarState.lockscreenPreviousBackgroundOpacity();\n','load opacity')
s=one(s,'            String(draftEntryTransitionDuration)\n','            String(draftEntryTransitionDuration),\n            String(draftLastBackgroundOpacity)\n','save opacity')
s=one(s,'    PanelWindow {\n        id: editorWindow\n','    PanelWindow {\n        id: editorWindow\n\n        Shortcut {\n            sequence: "Ctrl+A"\n            context: Qt.WindowShortcut\n            enabled: root.open && !root.pickerSuspended\n            onActivated: root.selectAllElements()\n        }\n','shortcut')
s=one(s,'                            const additive = !!(mouse.modifiers & Qt.ShiftModifier);\n                            root.selectElement(parent.elementName, additive);\n                            if (!root.selectedContains(parent.elementName))\n                                return;\n','                            const additive = !!(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier));\n                            if (additive) root.selectElement(parent.elementName, true);\n                            else if (!root.selectedContains(parent.elementName)) root.selectElement(parent.elementName, false);\n                            if (!root.selectedContains(parent.elementName))\n                                return;\n','ctrl selection')
s=rx(s,r'                        SettingsButton \{\n                            label: root\.selectedElement === "logo".*?\n                        \}\n\n                        SettingsButton \{\n                            label: "Reset Position"',r'''                        SettingsButton {
                            label: root.selectedElements.length > 1
                                ? (root.selectionAllVisible() ? "Hide Selected" : "Show Selected")
                                : root.selectedElement === "logo"
                                    ? (root.elementEnabled("logo") ? "Logo visible" : "Logo hidden")
                                    : root.elementCanHide(root.selectedElement)
                                        ? (root.elementEnabled(root.selectedElement) ? "Visible" : "Hidden") : "Always visible"
                            active: root.selectedElements.length > 1 ? root.selectionAllVisible() : root.elementEnabled(root.selectedElement)
                            available: root.selectedElements.length > 1
                                ? root.selectedElements.some(name => name !== "password" && root.elementCanHide(name))
                                : root.elementCanHide(root.selectedElement)
                            textSize: 9
                            onClicked: {
                                if (root.selectedElements.length > 1) root.setSelectedVisibility(!root.selectionAllVisible());
                                else root.setDraftVisible(root.selectedElement, !root.elementEnabled(root.selectedElement));
                            }
                        }

                        SettingsButton {
                            label: "Reset Position"''','visibility UI')
s=rx(s,r'                        Text \{\n                            text: Math\.round\(root\.elementScale\(root\.selectedElement\) \* 100\) \+ "%".*?\n                        \}\n',r'''                        TextField {
                            id: elementScaleField; Layout.preferredWidth: 58
                            text: Number(root.elementScale(root.selectedElement) * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 50; top: 10000; decimals: 1 }
                            selectByMouse: true; font.pixelSize: 9
                            onEditingFinished: root.setDraftScale(root.selectedElement, Number(text) / 100)
                        }
''','scale field')
s=rx(s,r'                        TextField \{\n                            Layout\.preferredWidth: 58\n                            visible: root\.isCustomImage\(root\.selectedElement\).*?\n                        \}\n',r'''                        TextField {
                            id: rotationField; Layout.preferredWidth: 68
                            visible: root.isCustomImage(root.selectedElement)
                            text: Number(root.elementRotation(root.selectedElement)).toFixed(1)
                            selectByMouse: true; font.pixelSize: 9
                            onEditingFinished: root.setDraftRotation(root.selectedElement, text)
                        }
                        SettingsButton { label: "0°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 0) }
                        SettingsButton { label: "90°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 90) }
                        SettingsButton { label: "180°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 180) }
                        SettingsButton { label: "270°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 270) }
''','rotation UI')
s=rx(s,r'                        Text \{\n                            text: Math\.round\(root\.elementOpacity\(root\.selectedElement\)\) \+ "%".*?\n                        \}\n',r'''                        TextField {
                            id: elementOpacityField; Layout.preferredWidth: 52
                            text: Number(root.elementOpacity(root.selectedElement)).toFixed(0)
                            validator: IntValidator { bottom: root.selectedElement === "password" ? 20 : 0; top: 100 }
                            selectByMouse: true; font.pixelSize: 9
                            onEditingFinished: root.setDraftOpacity(root.selectedElement, text)
                        }
''','opacity field')
s=one(s,'                        Text { text: Math.round(root.elementStretchX(root.selectedElement) * 100) + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignHCenter }\n','                        TextField { id: elementStretchXField; Layout.preferredWidth: 54; text: Number(root.elementStretchX(root.selectedElement) * 100).toFixed(1); validator: DoubleValidator { bottom: 25; top: 400; decimals: 1 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftStretch(root.selectedElement, Number(text) / 100, root.elementStretchY(root.selectedElement)) }\n','stretch x')
s=one(s,'                        Text { text: Math.round(root.elementStretchY(root.selectedElement) * 100) + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignHCenter }\n','                        TextField { id: elementStretchYField; Layout.preferredWidth: 54; text: Number(root.elementStretchY(root.selectedElement) * 100).toFixed(1); validator: DoubleValidator { bottom: 25; top: 400; decimals: 1 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftStretch(root.selectedElement, root.elementStretchX(root.selectedElement), Number(text) / 100) }\n','stretch y')
s=one(s,'                        TextField {\n                            Layout.preferredWidth: 58\n                            text: (Number(root.draftVisualizer.stretch_x || 1) * 100).toFixed(1)\n','                        TextField {\n                            id: visualizerWidthField\n                            Layout.preferredWidth: 58\n                            text: (Number(root.draftVisualizer.stretch_x || 1) * 100).toFixed(1)\n','viz width')
s=one(s,'                        Text { text: root.draftVisualizer.height + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter }\n','                        TextField { id: visualizerHeightField; Layout.preferredWidth: 48; text: String(root.draftVisualizer.height); validator: IntValidator { bottom: 25; top: 300 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftVisualizerSetting("height", text) }\n','viz height')
s=one(s,'                        Text { text: root.draftVisualizer.sensitivity + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter }\n','                        TextField { id: visualizerSensitivityField; Layout.preferredWidth: 48; text: String(root.draftVisualizer.sensitivity); validator: IntValidator { bottom: 25; top: 300 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftVisualizerSetting("sensitivity", text) }\n','viz sensitivity')
s=one(s,'                        SettingsButton { label: "Contain"; active: root.draftWallpaperFit === "contain"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("contain") }\n                        Text { text: "Brightness"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n','                        SettingsButton { label: "Contain"; active: root.draftWallpaperFit === "contain"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("contain") }\n                        Text { text: "Focal X"; visible: root.draftBackgroundMode === "wallpaper" && root.draftWallpaperFit === "cover"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n                        TextField { id: wallpaperFocalXField; visible: root.draftBackgroundMode === "wallpaper" && root.draftWallpaperFit === "cover"; Layout.preferredWidth: 54; text: Number(root.draftWallpaperFocalX * 100).toFixed(1); validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftWallpaperFocal(Number(text) / 100, root.draftWallpaperFocalY) }\n                        Text { text: "Focal Y"; visible: root.draftBackgroundMode === "wallpaper" && root.draftWallpaperFit === "cover"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n                        TextField { id: wallpaperFocalYField; visible: root.draftBackgroundMode === "wallpaper" && root.draftWallpaperFit === "cover"; Layout.preferredWidth: 54; text: Number(root.draftWallpaperFocalY * 100).toFixed(1); validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftWallpaperFocal(root.draftWallpaperFocalX, Number(text) / 100) }\n                        Text { text: "Brightness"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n','focal fields')
s=one(s,'                        Text { text: (root.draftBrightness() > 0 ? "+" : "") + root.draftBrightness() + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42 }\n','                        TextField { id: brightnessField; Layout.preferredWidth: 50; text: String(root.draftBrightness()); validator: IntValidator { bottom: -100; top: 100 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftBrightness(text) }\n','brightness field')
s=one(s,'                        Text { text: root.draftWallpaperBlur + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 34 }\n','                        TextField { id: blurField; Layout.preferredWidth: 46; text: String(root.draftWallpaperBlur); validator: IntValidator { bottom: 0; top: 100 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftWallpaperBlur(text) }\n','blur field')
s=one(s,'                        Text { text: root.draftBackgroundOpacity + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 36 }\n                        SettingsButton { label: "Opaque"; textSize: 9; active: root.draftBackgroundOpacity === 100; onClicked: root.setDraftBackgroundOpacity(100) }\n','                        TextField { id: backgroundOpacityField; Layout.preferredWidth: 46; text: String(root.draftBackgroundOpacity); validator: IntValidator { bottom: 0; top: 100 }; selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftBackgroundOpacity(text) }\n                        SettingsButton { label: "Opaque"; textSize: 9; active: root.draftBackgroundOpacity === 100; onClicked: root.toggleBackgroundOpaque() }\n','opacity UI')
variant='''

    Variants {
        id: editorPreviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: secondaryPreviewWindow
            required property var modelData
            screen: modelData
            visible: root.open && !root.pickerSuspended && editorWindow.visible
                && editorWindow.screen && modelData.name !== editorWindow.screen.name
            color: "transparent"; focusable: false; aboveWindows: true
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
            Item {
                id: secondaryTransitionStart; anchors.fill: parent
                Rectangle { anchors.fill: parent; color: "#101318" }
                Rectangle { anchors.centerIn: parent; width: parent.width*0.62; height: parent.height*0.56; radius: 8; color: "#202731"; border.width: 1; border.color: "#3a4657" }
            }
            LockPreviewScene {
                id: secondaryPreviewScene; anchors.fill: parent; theme: Theme
                animationPreference: BarState.lockscreenAnimationPreference()
                entryTransition: root.draftEntryTransition; entryTransitionDuration: root.draftEntryTransitionDuration
                externallyManagedEntryTransition: true; externalEntryTransitionRunning: secondaryPreviewTransitionLayer.running
                randomFormationMode: 3; logoPhysicsHz: BarState.lockscreenLogoPhysicsHz(); mouseInteractive: false
                showLogo: root.draftVisibility.logo; showTime: root.draftVisibility.time; showDate: root.draftVisibility.date
                showUsername: root.draftVisibility.username; showWeather: root.draftVisibility.weather
                weatherText: root.draftWeatherUnits === "celsius" ? "22°C · Clear" : "72°F · Clear"
                backgroundMode: root.draftBackgroundMode; wallpaperSource: wallpaperState.source; backgroundColor: root.draftBackgroundColor
                wallpaperFit: root.draftWallpaperFit; wallpaperFocalX: root.draftWallpaperFocalX; wallpaperFocalY: root.draftWallpaperFocalY
                overlayMode: root.draftOverlayMode; overlayStrength: root.draftOverlayStrength; wallpaperBlur: root.draftWallpaperBlur
                autoAccents: root.draftAutoAccents; layout: root.draftLayout; customImages: root.draftCustomImages
                visualizer: root.draftVisualizer; audioBands: previewAudioAnalyzer.bands; backgroundOpacity: root.draftBackgroundOpacity
                previewMode: true; editorMode: false
            }
            LockPreviewTransitionLayer {
                id: secondaryPreviewTransitionLayer; anchors.fill: parent; z: 160
                startSource: secondaryTransitionStart; endSource: secondaryPreviewScene
                mode: root.draftEntryTransition; duration: root.draftEntryTransitionDuration
                replayToken: root.entryTransitionReplayToken
            }
        }
    }
'''
if not s.endswith('\n}\n'): raise RuntimeError('editor final shape')
s=s[:-3]+variant+'\n}\n'; put(f,s)

# Updated contracts supersede older assumptions.
f='tests/test-quickshell-lockscreen-third-runtime-pass.sh'; s=get(f); s=s.replace("contains \"$SURFACE\" 'root.transitionComplete || root.wallpaperBlur <= 0'","contains \"$SURFACE\" '!root.transitionComplete || root.wallpaperBlur <= 0'"); put(f,s)
f='tests/test-quickshell-lockscreen-background-composition.sh'; s=get(f)
s=one(s,'# LockScene composes the configured background. Desktop-backing blur belongs outside it.\n','# LockScene composes configured wallpaper blur; LockSurface separately blurs the secure captured desktop backing.\n','bg comment')
s=one(s,"forbid_text \"$PREVIEW\" 'source: wallpaperImage' 'blur is still applied only to the configured wallpaper instead of the secure desktop backing'\n","require_text \"$PREVIEW\" 'id: wallpaperBlurEffect' 'wallpaper blur has no rendered effect path'\nrequire_text \"$PREVIEW\" 'source: wallpaperImage' 'wallpaper blur does not source the wallpaper image'\n",'bg contract'); put(f,s)
f='tests/test-quickshell-lockscreen-entry-transitions.sh'; s=get(f); s=s.replace("'logo/password entry gating is not coordinated with the shared renderer'","'logo entry gating is not coordinated with the shared renderer'"); put(f,s)

# Every changed managed file gets its exact current hash appended, never removing history.
hp=p('local/share/awtarchy/quickshell-managed-history.sha256'); h=hp.read_text(); lines=set(h.splitlines())
managed={
'config/hypr/scripts/quickshell_application_state.sh':'.config/hypr/scripts/quickshell_application_state.sh',
'config/quickshell/awtarchy/BarState.qml':'.config/quickshell/awtarchy/BarState.qml',
'config/quickshell/awtarchy/LockscreenEditor.qml':'.config/quickshell/awtarchy/LockscreenEditor.qml',
'config/quickshell/awtarchy/LockPreviewScene.qml':'.config/quickshell/awtarchy/LockPreviewScene.qml',
'config/quickshell/awtarchy/LockPreviewTransitionLayer.qml':'.config/quickshell/awtarchy/LockPreviewTransitionLayer.qml',
'config/quickshell/awtarchy-lock/LockSurface.qml':'.config/quickshell/awtarchy-lock/LockSurface.qml',
'config/quickshell/awtarchy-lock/LockScene.qml':'.config/quickshell/awtarchy-lock/LockScene.qml',
'config/quickshell/awtarchy-lock/LockTransitionLayer.qml':'.config/quickshell/awtarchy-lock/LockTransitionLayer.qml'}
add=[]
for src,dst in managed.items():
    line=f'{hashlib.sha256(p(src).read_bytes()).hexdigest()}\t{dst}'
    if line not in lines: add.append(line)
if add: hp.write_text(h.rstrip('\n')+'\n'+'\n'.join(add)+'\n')
print('applied third runtime pass')
