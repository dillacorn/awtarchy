import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "LockscreenPresentationState.js" as LockscreenPresentationState

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking
    required property var monitorProfiles
    required property var lastEditedProfile
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive
    required property string captureDirectory

    color: "#000000"

    readonly property string monitorName: root.screen && root.screen.name
        ? String(root.screen.name) : ""
    readonly property var profile: LockscreenPresentationState.profileForMonitor(
        root.monitorProfiles, root.lastEditedProfile, root.monitorName)
    readonly property string captureOutputName: root.monitorName
    readonly property string captureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".png"
        : ""
    readonly property string transitionCaptureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".transition.png"
        : ""
    readonly property bool transitionComplete: root.transitionStarted && !transitionLayer.running
    readonly property real uiScale: scene.uiScale
    readonly property real passwordScale: scene.elementScale("password")
    readonly property int maskedCount: root.passwordFailureMaskCount > 0
        ? root.passwordFailureMaskCount : Math.min(password.text.length, 10)
    readonly property real maskSpread: maskedCount === 0 ? 0
        : Math.round((24 + maskedCount * 14) * uiScale * passwordScale)
    readonly property string passwordFeedbackMode:
        String(root.profile.lockscreen_password_feedback_mode || "squares")
    readonly property bool passwordMaskVisible:
        ["squares", "dots", "custom"].indexOf(root.passwordFeedbackMode) >= 0

    property bool entered: false
    property bool transitionStarted: false
    property bool preRollSchedulingReady: false
    property int submittedMaskCount: 0
    property int passwordFailureMaskCount: 0
    property int passwordTypingEpoch: 0
    property int passwordFailureEpoch: 0
    property int previousPasswordLength: 0

    onPasswordFailureEpochChanged: {
        if (passwordFailureEpoch > 0)
            passwordFailureEdgeAnimation.restart();
    }

    property var localTimezoneValues: ({})
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string timezoneBackend: configHome
        + "/hypr/scripts/quickshell_lockscreen_timezones.sh"

    LockWallpaperState {
        id: lockWallpaperState
        path: root.profile.lockscreen_wallpaper_path
    }

    LockContrastCache {
        id: lockContrastCache
        monitorName: root.monitorName
    }

    LockWeatherCache {
        id: lockWeatherCache
        enabled: root.profile.lockscreen_show_weather
        units: root.profile.lockscreen_weather_units
    }

    LockAudioAnalyzer {
        id: lockAudioAnalyzer
        enabled: root.profile.lockscreen_visualizer.enabled
        performanceMode: root.profile.lockscreen_visualizer.performance
    }

    function refreshTimezoneValues() {
        const clocks = root.profile.lockscreen_timezone_clocks || [];
        if (!Array.isArray(clocks) || clocks.length === 0) {
            root.localTimezoneValues = ({});
            return;
        }
        if (timezoneProcess.running)
            return;
        const args = [root.timezoneBackend, "--batch"];
        for (const clock of clocks)
            args.push(String(clock.id), String(clock.timezone), String(clock.format || "24h"));
        timezoneProcess.exec(args);
    }

    function submitPassword() {
        if ((auth.busy && !auth.responseRequired) || password.text.length === 0)
            return;

        const response = password.text;
        root.submittedMaskCount = Math.min(response.length, 10);
        root.passwordFailureMaskCount = 0;
        if (auth.submit(response))
            password.text = "";
    }

    function focusPasswordWhenReady() {
        if (root.unlocking)
            return;
        Qt.callLater(() => {
            if (!root.unlocking)
                password.forceActiveFocus();
        });
    }

    function startEntryTransition() {
        if (!root.preRollSchedulingReady || root.transitionStarted || root.unlocking)
            return;
        videoPreRollTimeout.stop();
        // Keep the pending scene gate asserted until the transition reports
        // running, then release the frozen pre-roll cover.
        transitionLayer.restart();
        root.transitionStarted = true;
    }

    function scheduleEntryTransition() {
        if (!root.preRollSchedulingReady || root.transitionStarted || root.unlocking)
            return;
        if (!scene.backgroundMediaNeedsPreroll || scene.backgroundMediaPlaybackAdvanced) {
            root.startEntryTransition();
            return;
        }
        if (!videoPreRollTimeout.running)
            videoPreRollTimeout.restart();
    }

    Process {
        id: timezoneProcess
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(String(data || "{}"));
                    root.localTimezoneValues = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
                } catch (error) {
                    root.localTimezoneValues = ({});
                }
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: Array.isArray(root.profile.lockscreen_timezone_clocks)
            && root.profile.lockscreen_timezone_clocks.length > 0
        triggeredOnStart: true
        onTriggered: root.refreshTimezoneValues()
    }

    onProfileChanged: Qt.callLater(() => root.refreshTimezoneValues())

    PinchHandler {
        target: null
    }

    WheelHandler {
        target: null
    }

    // Keep the dirty/current-screen transition source outside the visible
    // secure composition. ShaderEffectSource can sample it, but background
    // transparency in LockScene can only reveal the clean desktop backing.
    Item {
        id: transitionBacking
        x: root.width + 64
        y: 0
        width: root.width
        height: root.height

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        Image {
            anchors.fill: parent
            source: root.transitionCaptureSource
            asynchronous: false
            cache: false
            fillMode: Image.Stretch
            visible: status === Image.Ready
        }
    }

    Item {
        id: securePresentation
        anchors.fill: parent

        // This backing is deliberately opaque even when capture loading fails.
        // Background transparency later reveals this secure frozen frame rather
        // than compositor pixels outside the WlSessionLock surface.
        Item {
            id: desktopBacking
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            Image {
                id: desktopCapture
                anchors.fill: parent
                source: root.captureSource
                asynchronous: false
                cache: false
                fillMode: Image.Stretch
                visible: status === Image.Ready
            }
        }

        LockScene {
            id: scene
            anchors.fill: parent
            theme: root.theme
            unlocking: root.unlocking
            animationPreference: root.profile.lockscreen_animation
            randomFormationMode: root.randomFormationMode
            logoPhysicsHz: root.logoPhysicsHz
            mouseInteractive: root.mouseInteractive && root.transitionComplete
            showLogo: root.profile.lockscreen_show_logo
            showTime: root.profile.lockscreen_show_time
            showDate: root.profile.lockscreen_show_date
            showUsername: root.profile.lockscreen_show_username
            showWeather: root.profile.lockscreen_show_weather
            weatherText: lockWeatherCache.summary
            backgroundMode: root.profile.lockscreen_background
            wallpaperSource: lockWallpaperState.source
            backgroundColor: root.profile.lockscreen_background_color
            wallpaperFit: root.profile.lockscreen_wallpaper_fit
            wallpaperFocalX: root.profile.lockscreen_wallpaper_focal_x
            wallpaperFocalY: root.profile.lockscreen_wallpaper_focal_y
            overlayMode: root.profile.lockscreen_overlay_mode
            overlayStrength: root.profile.lockscreen_overlay_strength
            wallpaperBlur: root.profile.lockscreen_wallpaper_blur
            blurStyle: root.profile.lockscreen_blur_style
            autoAccents: lockContrastCache.colors
            layout: root.profile.lockscreen_layout
            customImages: root.profile.lockscreen_custom_images
            timezoneClocks: root.profile.lockscreen_timezone_clocks
            timezoneValues: root.localTimezoneValues
            customTexts: root.profile.lockscreen_custom_texts
            visualizer: root.profile.lockscreen_visualizer
            audioBands: lockAudioAnalyzer.bands
            backgroundOpacity: root.profile.lockscreen_background_opacity
            passwordMaskMode: root.profile.lockscreen_password_feedback_mode
            passwordMaskCharacter: root.profile.lockscreen_password_mask_character
            passwordFeedbackEpoch: root.passwordTypingEpoch
            clockFormat: root.profile.lockscreen_clock_format
            desktopBackingSource: desktopBacking
            previewMode: false
            externalEntryTransitionRunning: transitionLayer.running
            externalEntryTransitionPending: !root.transitionStarted
        }
    }

    // While a video destination decodes its first frames, keep the secure
    // captured desktop visible. The live destination continues rendering below.
    ShaderEffectSource {
        id: preRollCover
        anchors.fill: parent
        z: 999
        sourceItem: transitionBacking
        live: true
        recursive: false
        smooth: true
        visible: !root.transitionStarted
    }

    Timer {
        id: videoPreRollTimeout
        interval: 750
        repeat: false
        onTriggered: root.startEntryTransition()
    }

    // Double the active interaction cadence without adding any idle polling.
    // The scene still owns all particle physics and its normal settle condition.
    Timer {
        id: logoInteractionBoost
        interval: scene.logoPhysicsIntervalMs
        repeat: true
        running: scene.logoSimulationActive
        onTriggered: scene.stepLogoExplosion()
    }

    Connections {
        target: scene

        function onLogoExplosionActiveChanged() {
            if (!scene.logoExplosionActive && Object.keys(scene.logoParticles).length > 0) {
                scene.logoReturnPending = true;
                scene.logoHoverDirty = true;
            }
        }

        function onBackgroundMediaNeedsPrerollChanged() {
            root.scheduleEntryTransition();
        }

        function onBackgroundMediaPlaybackAdvancedChanged() {
            root.scheduleEntryTransition();
        }
    }

    LockTransitionLayer {
        id: transitionLayer
        anchors.fill: parent
        z: 1000
        startSource: transitionBacking
        endSource: securePresentation
        mode: root.profile.lockscreen_entry_transition
        duration: root.profile.lockscreen_entry_transition_duration
        replayToken: 0
        autoStart: false

        onFinished: {
            root.entered = true;
            root.focusPasswordWhenReady();
        }
    }

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        z: 10
        enabled: root.transitionComplete
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => scene.handlePointerMotion(mouse.x, mouse.y)
        onExited: scene.handlePointerExit()
        onClicked: mouse => {
            scene.handlePointerClick(mouse.x, mouse.y);
            password.forceActiveFocus();
        }
        onWheel: wheel => { wheel.accepted = true; }
    }

    Item {
        id: passwordBlock
        x: scene.passwordCenterX - width / 2
        y: scene.passwordCenterY - height / 2
        width: scene.passwordWidth
        height: scene.passwordHeight
        z: 1100
        opacity: (root.unlocking ? 0 : root.entered ? 1 : 0) * scene.elementOpacity("password")
        rotation: scene.elementRotation("password")
        transformOrigin: Item.Center
        transform: Scale {
            origin.x: passwordBlock.width / 2
            origin.y: passwordBlock.height / 2
            xScale: scene.elementStretchX("password")
            yScale: scene.elementStretchY("password")
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 220
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: passwordMaskRow
            anchors.centerIn: parent
            visible: root.passwordMaskVisible
            spacing: Math.round(7 * root.uiScale * root.passwordScale)

            Repeater {
                model: root.maskedCount

                Item {
                    width: scene.effectivePasswordMaskMode === "custom"
                        ? Math.round(12 * root.uiScale * root.passwordScale)
                        : Math.round(8 * root.uiScale * root.passwordScale)
                    height: Math.round(14 * root.uiScale * root.passwordScale)

                    Rectangle {
                        anchors.centerIn: parent
                        visible: scene.effectivePasswordMaskMode !== "custom"
                        width: scene.effectivePasswordMaskMode === "dots"
                            ? Math.round(8 * root.uiScale * root.passwordScale)
                            : Math.round(7 * root.uiScale * root.passwordScale)
                        height: scene.effectivePasswordMaskMode === "dots" ? width
                            : Math.round(10 * root.uiScale * root.passwordScale)
                        radius: scene.effectivePasswordMaskMode === "dots" ? width / 2 : 0
                        color: root.auth.statusIsError || root.passwordFailureMaskCount > 0
                            ? "#ff4d4d" : scene.elementColor("password")
                        opacity: 0.82
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: scene.effectivePasswordMaskMode === "custom"
                        text: scene.effectivePasswordMaskCharacter
                        color: root.auth.statusIsError || root.passwordFailureMaskCount > 0
                            ? "#ff4d4d" : scene.elementColor("password")
                        opacity: 0.82
                        font.family: root.theme.fontFamily
                        font.pixelSize: Math.round(16 * root.uiScale * root.passwordScale)
                    }
                }
            }
        }

        TextInput {
            id: password
            anchors.fill: parent

            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorDelegate: Item {
        width: 0
        height: 0
        visible: false
    }
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale * root.passwordScale)
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            enabled: !auth.busy || auth.responseRequired
            activeFocusOnTab: true

            onTextChanged: {
                const nextLength = text.length;
                if (nextLength > root.previousPasswordLength
                        && (root.passwordFeedbackMode === "sparks"
                            || root.passwordFeedbackMode === "mini-flash"))
                    root.passwordTypingEpoch += 1;
                root.previousPasswordLength = nextLength;
                if (nextLength > 0) {
                    root.passwordFailureMaskCount = 0;
                    if (root.auth.statusIsError)
                        root.auth.clearStatus();
                }
            }

            Keys.onReturnPressed: event => {
                root.submitPassword();
                event.accepted = true;
            }

            Keys.onEnterPressed: event => {
                root.submitPassword();
                event.accepted = true;
            }

            Keys.onEscapePressed: event => {
                password.text = "";
                auth.clearStatus();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        id: passwordFailureEdge
        anchors.fill: parent
        z: 1300
        color: "transparent"
        border.color: "#ff3030"
        border.width: Math.max(3, Math.round(7 * root.uiScale))
        opacity: 0
        visible: opacity > 0
    }

    SequentialAnimation {
        id: passwordFailureEdgeAnimation
        running: false
        PropertyAction {
            target: passwordFailureEdge
            property: "opacity"
            value: 0.72
        }
        PauseAnimation { duration: 45 }
        NumberAnimation {
            target: passwordFailureEdge
            property: "opacity"
            to: 0
            duration: 380
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: root.auth

        function onAuthenticationFailed() {
            root.passwordFailureEpoch += 1;
            root.passwordFailureMaskCount = Math.max(1, root.submittedMaskCount);
            password.text = "";
            root.focusPasswordWhenReady();
        }

        function onBusyChanged() {
            if (!root.auth.busy)
                root.focusPasswordWhenReady();
        }

        function onResponseRequiredChanged() {
            if (root.auth.responseRequired)
                root.focusPasswordWhenReady();
        }
    }

    Component.onCompleted: {
        root.entered = true;
        root.preRollSchedulingReady = true;
        root.scheduleEntryTransition();
        root.focusPasswordWhenReady();
    }
}
