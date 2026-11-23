pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// A compact author identity (the Dart AuthorAvatar): the monogram in the
// author's colour, with the Gravatar image once the person enabled author
// images; until then pressing it explains Gravatar and offers to enable it.
MeridianAvatar {
    id: avatar

    property string author
    property string avatarHash
    readonly property bool gravatar: Store.appearance.gravatarEnabled === true

    function load() {
        if (gravatar && avatarHash.length === 64 && Store.workflows)
            Store.workflows.requestAvatar(avatarHash)
    }

    name: author.split("<")[0].trim()
    colorKey: author
    avatarSize: MeridianAvatar.Small
    source: gravatar && Store.workflows && Store.workflows.avatars ? (Store.workflows.avatars[avatarHash] ?? "") : ""
    onAvatarHashChanged: load()
    onGravatarChanged: load()
    Component.onCompleted: load()

    HoverHandler {
        id: hover
        enabled: !avatar.gravatar
        cursorShape: Qt.PointingHandCursor
    }
    MeridianTooltip { shown: hover.hovered && !avatar.gravatar; text: L10n.t("avatarGravatarTooltip") }
    TapHandler {
        enabled: !avatar.gravatar
        onTapped: Store.actions.offerGravatar()
    }
}
