import QtQuick

// A spring token as a fixed-duration spline for Easing.BezierSpline.
QtObject {
    property string name
    property bool reduced: false
    readonly property int duration: reduced ? 0 : Tokens.springs[name].duration
    readonly property var curve: Tokens.springs[name].curve
}
