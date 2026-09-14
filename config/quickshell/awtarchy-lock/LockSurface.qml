import QtQuick
import QtQuick.Effects
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking
    required property string animationPreference
    required property string entryTransition
    required property int entryTransitionDuration
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive
    required property bool showLogo
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText
    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property string wallpaperFit
    required property real wallpaperFocalX
    required property real wallpaperFocalY
    required property string overlayMode
    required property real overlayStrength
    required property real wallpaperBlur
    required property string blurStyle
    required property var autoAccents
    required property var layout
    required property var customImages
    required property var timezoneClocks
    required property var timezoneValues
    required property var customTexts
    required property var visualizer
    required property var audioBands
    required property int backgroundOpacity
    required property string passwordMaskMode
    required property string passwordMaskCharacter
    required property string clockFormat
    required property string captureDirectory

    color: "#000000"

    readonly property string captureOutputName: root.screen && root.screen.name
        ? String(root.screen.name) : ""
    readonly property string captureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".png"
        : ""
    readonly property bool transitionComplete: !transitionLayer.running
    readonly property real uiScale: scene.uiScale
    readonly property real passwordScale: scene.elementScale("password")
    readonly property int maskedCount: root.passwordFailureMaskCount > 0
        ? root.passwordFailureMaskCount : Math.min(password.text.length, 10)
    readonly property real maskSpread: maskedCount === 0 ? 0
        : Math.round((24 + maskedCount * 14) * uiScale * passwordScale)

    property bool entered: false
    property int submittedMaskCount: 0
    property int passwordFailureMaskCount: 0

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

    PinchHandler {
        target: null
    }

    WheelHandler {
        target: null
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
            animationPreference: root.animationPreference
            randomFormationMode: root.randomFormationMode
            logoPhysicsHz: root.logoPhysicsHz
            mouseInteractive: root.mouseInteractive && root.transitionComplete
            showLogo: root.showLogo
            showTime: root.showTime
            showDate: root.showDate
            showUsername: root.showUsername
            showWeather: root.showWeather
            weatherText: root.weatherText
            backgroundMode: root.backgroundMode
            wallpaperSource: root.wallpaperSource
            backgroundColor: root.backgroundColor
            wallpaperFit: root.wallpaperFit
            wallpaperFocalX: root.wallpaperFocalX
            wallpaperFocalY: root.wallpaperFocalY
            overlayMode: root.overlayMode
            overlayStrength: root.overlayStrength
            wallpaperBlur: root.wallpaperBlur
            blurStyle: root.blurStyle
            autoAccents: root.autoAccents
            layout: root.layout
            customImages: root.customImages
            timezoneClocks: root.timezoneClocks
            timezoneValues: root.timezoneValues
            customTexts: root.customTexts
            visualizer: root.visualizer
            audioBands: root.audioBands
            backgroundOpacity: root.backgroundOpacity
            passwordMaskMode: root.passwordMaskMode
            passwordMaskCharacter: root.passwordMaskCharacter
            clockFormat: root.clockFormat
            desktopBackingSource: desktopBacking
            previewMode: false
            externalEntryTransitionRunning: transitionLayer.running
        }
    }

    LockTransitionLayer {
        id: transitionLayer
        anchors.fill: parent
        z: 1000
        startSource: desktopBacking
        endSource: securePresentation
        mode: root.entryTransition
        duration: root.entryTransitionDuration
        replayToken: 0

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
            anchors.centerIn: parent
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
                if (text.length > 0) {
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

    Connections {
        target: root.auth

        function onAuthenticationFailed() {
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
        root.focusPasswordWhenReady();
    }
}
