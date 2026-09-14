import QtQuick
import "../LockscreenPresentationState.js" as LockscreenPresentationState

LockSceneBase {
    id: root

    textReplayEpoch: Math.floor(Math.random() * 2147483647)

    function refreshCustomTextSelections() {
        const next = ({});
        if (Array.isArray(root.customTexts)) {
            for (const item of root.customTexts) {
                if (!item)
                    continue;
                next[String(item.id)] = LockscreenPresentationState.textForPresentation(
                    item, root.textReplayEpoch);
            }
        }
        root.customTextSelections = next;
    }
}
