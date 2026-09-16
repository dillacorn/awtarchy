#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"missing/ambiguous patch target: {label}")
    return text.replace(old, new, 1)


media = '''import QtQuick
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
'''

for media_path in (
    Path("config/quickshell/awtarchy-lock/LockMedia.qml"),
    Path("config/quickshell/awtarchy/LockMedia.qml"),
):
    media_path.write_text(media)

scene_path = Path("config/quickshell/awtarchy-lock/LockScene.qml")
text = scene_path.read_text()
text = replace_once(
    text,
    '        const sourceWidth = Number(wallpaperImage.sourceSize.width);\n        const sourceHeight = Number(wallpaperImage.sourceSize.height);',
    '        const sourceWidth = Number(wallpaperMedia.sourceSize.width);\n        const sourceHeight = Number(wallpaperMedia.sourceSize.height);',
    "background media source size",
)
text = replace_once(
    text,
    '''            Image {
                id: wallpaperImage
                readonly property var geometry: root.wallpaperGeometry()
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
                source: root.wallpaperSource
                fillMode: Image.Stretch
                asynchronous: true
                cache: true
            }
''',
    '''            LockMedia {
                id: wallpaperMedia
                readonly property var geometry: root.wallpaperGeometry()
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
                active: visible
                source: root.wallpaperSource
                contentFit: "stretch"
            }
''',
    "background media renderer",
)
text = replace_once(
    text,
    '''                Image {
                    id: customImageSource
                    anchors.fill: parent
                    source: String(customImageDelegate.modelData.path || "").startsWith("/")
                        ? "file://" + String(customImageDelegate.modelData.path) : ""
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectFit
                    smooth: customImageDelegate.spawnMode !== "pixel-warp" || customImageDelegate.effectiveSpawnProgress >= 0.999
                }
''',
    '''                LockMedia {
                    id: customImageSource
                    anchors.fill: parent
                    active: customImageDelegate.visible
                    source: String(customImageDelegate.modelData.path || "").startsWith("/")
                        ? "file://" + String(customImageDelegate.modelData.path) : ""
                    contentFit: "contain"
                    mediaSmooth: customImageDelegate.spawnMode !== "pixel-warp" || customImageDelegate.effectiveSpawnProgress >= 0.999
                }
''',
    "custom media renderer",
)
scene_path.write_text(text)
Path("config/quickshell/awtarchy/LockPreviewScene.qml").write_text(text)
