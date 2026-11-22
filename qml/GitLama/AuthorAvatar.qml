import QtQuick
import Meridian

// A compact author identity (AuthorAvatar): the monogram in the author's
// colour. Gravatar images arrive when the person enabled them.
MeridianAvatar {
    property string author
    property string avatarHash

    name: author.split("<")[0].trim()
    colorKey: author
    avatarSize: MeridianAvatar.Small
}
