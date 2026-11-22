pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T

// A month calendar (Flutter: MeridianDatePicker). Weekdays follow `locale`
// (first day and narrow names); set the control's `locale` to the regional
// locale. Today has an `accent` ring; the chosen day is
// solid `accent`; days outside [firstDate, lastDate] cannot be chosen. The
// grid is one tab stop: arrows move a day or a week, Page Up and Page Down a
// month, Home and End the ends of the week, Enter or Space chooses.
T.Control {
    id: root

    property date selectedDate: new Date(NaN)
    property date firstDate: new Date(1900, 0, 1)
    property date lastDate: new Date(2200, 11, 31)
    property string previousMonthLabel
    property string nextMonthLabel
    property date focusDate: _valid(selectedDate) ? selectedDate : new Date()
    property date today: new Date()

    signal dateChosen(date value)

    readonly property int month: focusDate.getMonth()
    readonly property int year: focusDate.getFullYear()
    readonly property int firstWeekday: locale.firstDayOfWeek % 7
    readonly property date gridStart: {
        const first = new Date(year, month, 1)
        const offset = (first.getDay() - firstWeekday + 7) % 7
        return new Date(year, month, 1 - offset)
    }
    readonly property real cell: Theme.touch ? 40 : 32

    focusPolicy: Qt.StrongFocus
    padding: Theme.space.s4
    implicitWidth: 7 * cell + leftPadding + rightPadding
    implicitHeight: header.height + weekdays.height + 6 * cell + Theme.space.s3 * 2 + topPadding + bottomPadding

    Accessible.role: Accessible.Table
    Accessible.name: locale.standaloneMonthName(month) + " " + year

    function _valid(d) { return d instanceof Date && !isNaN(d.getTime()) }
    function _day(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function _same(a, b) {
        return _valid(a) && _valid(b) && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function inRange(d) { return _day(d) >= _day(firstDate) && _day(d) <= _day(lastDate) }
    function moveDays(n) {
        const d = new Date(focusDate.getFullYear(), focusDate.getMonth(), focusDate.getDate() + n)
        if (inRange(d)) focusDate = d
    }
    function moveMonths(n) {
        const target = new Date(focusDate.getFullYear(), focusDate.getMonth() + n, 1)
        const last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
        const d = new Date(target.getFullYear(), target.getMonth(), Math.min(focusDate.getDate(), last))
        if (inRange(d)) focusDate = d
    }
    function choose(d) {
        if (!inRange(d)) return
        focusDate = d
        selectedDate = d
        dateChosen(d)
    }

    Keys.onLeftPressed: moveDays(-1)
    Keys.onRightPressed: moveDays(1)
    Keys.onUpPressed: moveDays(-7)
    Keys.onDownPressed: moveDays(7)
    Keys.onPressed: event => {
        const weekday = (focusDate.getDay() - firstWeekday + 7) % 7
        switch (event.key) {
        case Qt.Key_PageUp: moveMonths(-1); break
        case Qt.Key_PageDown: moveMonths(1); break
        case Qt.Key_Home: moveDays(-weekday); break
        case Qt.Key_End: moveDays(6 - weekday); break
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: choose(focusDate); break
        default: return
        }
        event.accepted = true
    }

    background: Item {}

    contentItem: Column {
        spacing: Theme.space.s3
        Item {
            id: header
            width: parent.width
            height: Theme.size.control
            MeridianText {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.space.s3
                role: MeridianText.BodyStrong
                text: root.locale.standaloneMonthName(root.month) + " " + root.year
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                MeridianIconButton {
                    objectName: "datePickerPrevious"
                    iconName: "chevron-left"
                    text: root.previousMonthLabel
                    focusPolicy: Qt.NoFocus
                    onClicked: root.moveMonths(-1)
                }
                MeridianIconButton {
                    objectName: "datePickerNext"
                    iconName: "chevron-right"
                    text: root.nextMonthLabel
                    focusPolicy: Qt.NoFocus
                    onClicked: root.moveMonths(1)
                }
            }
        }
        Row {
            id: weekdays
            Repeater {
                model: 7
                delegate: MeridianText {
                    required property int index
                    width: root.cell
                    horizontalAlignment: Text.AlignHCenter
                    role: MeridianText.Caption
                    color: Theme.colors.inkMuted
                    text: root.locale.dayName((root.firstWeekday + index) % 7, Locale.NarrowFormat)
                }
            }
        }
        Grid {
            columns: 7
            Repeater {
                model: 42
                delegate: T.AbstractButton {
                    id: day
                    required property int index
                    readonly property date date: new Date(root.gridStart.getFullYear(), root.gridStart.getMonth(),
                                                          root.gridStart.getDate() + index)
                    readonly property bool outside: date.getMonth() !== root.month
                    readonly property bool usable: root.inRange(date)
                    readonly property bool chosen: root._same(date, root.selectedDate)
                    readonly property bool isToday: root._same(date, root.today)
                    readonly property bool focused: root.activeFocus && root._same(date, root.focusDate)
                    objectName: "day-" + date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate()
                    width: root.cell
                    height: root.cell
                    hoverEnabled: usable
                    focusPolicy: Qt.NoFocus
                    enabled: usable
                    text: date.getDate()
                    Accessible.name: date.toLocaleDateString(root.locale, Locale.LongFormat)
                    Accessible.selected: chosen
                    onClicked: {
                        root.forceActiveFocus(Qt.MouseFocusReason)
                        root.choose(date)
                    }
                    contentItem: MeridianText {
                        horizontalAlignment: Text.AlignHCenter
                        role: day.chosen || day.isToday ? MeridianText.BodyStrong : MeridianText.Body
                        text: day.text
                        color: day.chosen ? Theme.colors.inkOnAccent
                             : !day.usable ? Theme.colors.inkFaint
                             : day.isToday ? Theme.colors.accentInk
                             : day.outside ? Theme.colors.inkMuted : Theme.colors.ink
                        tabular: true
                    }
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: width / 2
                        color: day.chosen ? Theme.colors.accent
                             : day.hovered ? Theme.colors.paneHover : Theme.clear(Theme.colors.paneHover)
                        border.width: day.isToday && !day.chosen ? 1 : 0
                        border.color: Theme.colors.accent
                        MeridianFocusRing {
                            target: parent
                            shown: day.focused && root.visualFocus
                            targetRadius: parent.radius
                        }
                    }
                }
            }
        }
    }
}
