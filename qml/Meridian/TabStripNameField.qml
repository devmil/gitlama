import QtQuick

// A name edited in place (internal): starts with `initial` selected; Enter or
// leaving the field keeps it, Escape cancels (`done(null)`).
MeridianTextField {
    id: field

    property string initial
    property string placeholder
    property string accessibleName
    property int maxLength: -1
    property real fieldHeight: Metrics.tabPillHeight
    property bool _done: false
    signal done(var name)

    variant: MeridianTextField.Plain
    controlSize: MeridianButton.Small
    height: fieldHeight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    font: Theme.type.label
    text: initial
    placeholderText: placeholder
    maximumLength: maxLength > 0 ? maxLength : 32767
    Accessible.name: accessibleName

    function finish(name) {
        if (_done)
            return
        _done = true
        done(name)
    }

    // Focus moves after the loader that created the field has settled, and
    // leaving the field finishes after the focus change, so neither runs
    // inside the strip's own bindings.
    Component.onCompleted: Qt.callLater(() => {
        forceActiveFocus()
        selectAll()
    })
    onAccepted: finish(text)
    onActiveFocusChanged: if (!activeFocus) Qt.callLater(() => { if (!activeFocus) finish(text) })
    Keys.onEscapePressed: finish(null)
}
