import QtQuick
import QtMultimedia

Item {
    id: root

    property string source: ""
    property bool active: true
    property string contentFit: "stretch"
    property bool mediaSmooth: true
    property int videoFrameCount: 0

    readonly property string normalizedSource: {
        let value = String(root.source || "").toLowerCase();
        const query = value.indexOf("?");
        if (query >= 0)
            value = value.slice(0, query);
        const fragment = value.indexOf("#");
        if (fragment >= 0)
            value = value.slice(0, fragment);
        return value;
    }
    readonly property string mediaKind: {
        const normalized = root.normalizedSource;
        if (normalized.endsWith(".gif"))
            return "gif";
        if (normalized.endsWith(".mp4"))
            return "video";
        return normalized.length > 0 ? "image" : "none";
    }
    readonly property int imageFillMode: root.contentFit === "contain"
        ? Image.PreserveAspectFit
        : root.contentFit === "cover" ? Image.PreserveAspectCrop : Image.Stretch
    readonly property int videoFillMode: root.contentFit === "contain"
        ? VideoOutput.PreserveAspectFit
        : root.contentFit === "cover" ? VideoOutput.PreserveAspectCrop : VideoOutput.Stretch
    readonly property bool playbackAdvanced: videoFrameCount >= 2
    readonly property bool ready: root.mediaKind === "image"
        ? staticImage.status === Image.Ready
        : root.mediaKind === "gif"
            ? animatedImage.status === Image.Ready
            : root.mediaKind === "video" ? root.videoFrameCount > 0 : false
    readonly property size sourceSize: root.mediaKind === "video"
        ? (videoOutput.videoSink ? videoOutput.videoSink.videoSize : Qt.size(0, 0))
        : root.mediaKind === "gif" ? animatedImage.sourceSize : staticImage.sourceSize
    readonly property string errorString: root.mediaKind === "video"
        ? String(videoPlayer.errorString || "") : ""

    onSourceChanged: root.videoFrameCount = 0
    onMediaKindChanged: root.videoFrameCount = 0
    onActiveChanged: {
        if (!root.active)
            root.videoFrameCount = 0;
    }

    Image {
        id: staticImage
        anchors.fill: parent
        visible: root.active && root.mediaKind === "image"
        source: visible ? root.source : ""
        fillMode: root.imageFillMode
        asynchronous: true
        cache: true
        smooth: root.mediaSmooth
    }

    AnimatedImage {
        id: animatedImage
        anchors.fill: parent
        visible: root.active && root.mediaKind === "gif"
        source: visible ? root.source : ""
        fillMode: root.imageFillMode
        asynchronous: true
        cache: false
        playing: visible
        smooth: root.mediaSmooth
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        visible: root.active && root.mediaKind === "video"
        fillMode: root.videoFillMode
    }

    MediaPlayer {
        id: videoPlayer
        source: root.active && root.mediaKind === "video" ? root.source : ""
        videoOutput: videoOutput
        autoPlay: true
        loops: MediaPlayer.Infinite
        activeAudioTrack: -1
    }

    Connections {
        target: videoOutput.videoSink

        function onVideoFrameChanged(frame) {
            if (root.active && root.mediaKind === "video")
                root.videoFrameCount += 1;
        }
    }

    Component.onDestruction: videoPlayer.stop()
}
