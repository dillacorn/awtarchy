import Quickshell
import Quickshell.Wayland

// Sway-only replacement for application-toplevel flyouts. The upstream
// Awtarchy FloatingWindow is intentionally left untouched on Hyprland.
//
// A native layer-shell surface never enters Sway's tiling tree. Its size and
// edge offset are known BEFORE the first visible frame, so there is no
// tile -> float -> resize -> move transition.
//
// The facade properties are deliberately restricted to the upstream
// FloatingWindow properties consumed by the seven managed flyouts.
PanelWindow {
    id: popup

    property string title: ""
    property string placement: "center"
    property string surfaceRole: ""
    // Notification Center anchors to the clicked bar button, not screen center.
    property real edgeAnchor: -1
    property size minimumSize: Qt.size(1, 1)
    property size maximumSize: Qt.size(10000, 10000)

    visible: false
    focusable: true
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "awtarchy-sway-flyout"

    // Two adjacent anchors preserve the window's requested size rather than
    // stretching it to an entire monitor. The margins are output-local.
    anchors {
        left: true
        top: true
    }
    margins {
        left: popup.offsetX
        top: popup.offsetY
    }

    readonly property int outputWidth: Math.max(1,
        Math.round(screen ? Number(screen.width) || 1920 : 1920))
    readonly property int outputHeight: Math.max(1,
        Math.round(screen ? Number(screen.height) || 1080 : 1080))
    readonly property int panelWidth: Math.max(1,
        Math.min(outputWidth - 1, Math.round(implicitWidth || 1)))
    readonly property int panelHeight: Math.max(1,
        Math.min(outputHeight - 1, Math.round(implicitHeight || 1)))
    readonly property bool verticalEdge: placement === "left"
        || placement === "right" || placement === "left-center"
        || placement === "right-center"
    readonly property int barOffset: placement === "center" ? 0
        : BarState.barSizeFor(screen ? screen.name : "", verticalEdge)

    function clamp(value, high) {
        return Math.max(0, Math.min(Math.max(0, high), Math.round(value)));
    }

    // Match quickshell_flyout_prepare.sh: launcher aligns to the Apps end,
    // clipboard / Quick Settings center along the bar, connectivity and
    // battery menus align to the far corner, and Notification Center follows
    // the clicked bell position. All coordinates are local to popup.screen.
    readonly property bool cornerRole: surfaceRole === "network"
        || surfaceRole === "bluetooth" || surfaceRole === "battery"
    readonly property bool notificationRole: surfaceRole === "notifications"
    readonly property int notificationAnchorX: edgeAnchor >= 0
        ? Math.round(edgeAnchor) : outputWidth - 40
    readonly property int notificationAnchorY: edgeAnchor >= 0
        ? Math.round(edgeAnchor) : outputHeight - 40

    readonly property int offsetX: {
        const center = Math.round((outputWidth - panelWidth) / 2);
        const left = barOffset;
        const right = outputWidth - panelWidth - barOffset;
        if (placement === "left" || placement === "left-center")
            return clamp(left, outputWidth - panelWidth);
        if (placement === "right" || placement === "right-center")
            return clamp(right, outputWidth - panelWidth);
        if (notificationRole && (placement === "top" || placement === "bottom"))
            return clamp(Math.max(6, Math.min(outputWidth - panelWidth - 6,
                notificationAnchorX - panelWidth)), outputWidth - panelWidth);
        if (cornerRole && (placement === "top" || placement === "bottom"))
            return clamp(outputWidth - panelWidth - 8, outputWidth - panelWidth);
        if (surfaceRole === "launcher"
            && (placement === "top" || placement === "bottom"))
            return 0;
        return clamp(center, outputWidth - panelWidth);
    }

    readonly property int offsetY: {
        const center = Math.round((outputHeight - panelHeight) / 2);
        const top = barOffset;
        const bottom = outputHeight - panelHeight - barOffset;
        if (placement === "top" || placement === "top-center")
            return clamp(top, outputHeight - panelHeight);
        if (placement === "bottom" || placement === "bottom-center")
            return clamp(bottom, outputHeight - panelHeight);
        if (notificationRole && (placement === "left" || placement === "right"))
            return clamp(Math.max(6, Math.min(outputHeight - panelHeight - 6,
                notificationAnchorY - panelHeight)), outputHeight - panelHeight);
        if (cornerRole && (placement === "left" || placement === "right"))
            return clamp(outputHeight - panelHeight - 8, outputHeight - panelHeight);
        if (surfaceRole === "launcher"
            && (placement === "left" || placement === "right"))
            return 0;
        return clamp(center, outputHeight - panelHeight);
    }
}
