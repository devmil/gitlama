import QtQuick
import QtTest
import Meridian
import GitLama

// The diff shows its lines and scrolls: vertically with the wheel, and its
// text sideways under the fixed gutters with Shift+wheel, a sideways swipe or
// the sideways part of a diagonal one.
Item {
    id: root
    width: 500
    height: 300

    function line(index, kind, text) {
        return {
            stableId: "line-" + index, kind: kind, loading: false,
            oldLine: kind === "addition" ? 0 : index, newLine: kind === "deletion" ? 0 : index,
            text: text, runsOld: [], runsNew: [], marks: [], fileKind: "text",
            oldPath: "a.txt", newPath: "a.txt", invalid: false, hunkRange: "", hunkText: ""
        }
    }

    // Stands in for the Rust diff model: the rows plus the calls DiffView makes.
    function fakeModel(count) {
        const rows = [line(0, "hunk", "@@ -1 +1 @@")]
        for (let i = 1; i < count; ++i)
            rows.push(line(i, i % 3 === 0 ? "addition" : i % 3 === 1 ? "deletion" : "context",
                           i === 2 ? "x".repeat(400) : "line " + i))
        rows.count = () => rows.length
        rows.setLatin1 = () => {}
        rows.setPalette = () => {}
        rows.demandSyntax = () => {}
        rows.changeMap = buckets => new Array(buckets).fill(0)
        rows.hunkHeaderFor = () => null
        rows.hunkFrom = () => -1
        rows.lineIds = (first, last) => rows.slice(first, last + 1).map(row => row.stableId)
        rows.firstIndexOf = () => -1
        rows.selectionText = () => ""
        rows.selectionHasChange = () => false
        rows.textBetween = () => ""
        return rows
    }

    Component {
        id: diffComponent
        DiffView { width: root.width; height: root.height }
    }

    TestCase {
        name: "DiffView"
        when: windowShown

        function makeDiff(count) {
            const diff = createTemporaryObject(diffComponent, root)
            verify(diff !== null)
            diff.model = fakeModel(count)
            tryVerify(() => diff.maximumOffset > 0, 2000, "the long line is wider than the view")
            return diff
        }
        function list(diff) {
            let found = null
            const visit = item => {
                for (const child of item.children) {
                    if (found)
                        return
                    if (child instanceof ListView) {
                        found = child
                        return
                    }
                    visit(child)
                }
            }
            visit(diff)
            verify(found !== null)
            return found
        }

        function test_lines_render() {
            const diff = makeDiff(60)
            const view = list(diff)
            tryVerify(() => view.count === 60)
            verify(view.contentHeight > diff.height)
        }

        function test_wheel_scrolls_vertically_only() {
            const diff = makeDiff(200)
            const view = list(diff)
            mouseWheel(view, 100, 100, 0, -240)
            tryVerify(() => view.contentY > 0, 2000)
            compare(diff.textOffset, 0)
        }

        function test_shift_wheel_scrolls_text_sideways() {
            const diff = makeDiff(60)
            const view = list(diff)
            mouseWheel(view, 100, 100, 0, -120, Qt.NoButton, Qt.ShiftModifier)
            tryVerify(() => diff.textOffset > 0, 2000)
            compare(view.contentY, view.originY)
        }

        function test_sideways_swipe_scrolls_text() {
            const diff = makeDiff(60)
            const view = list(diff)
            mouseWheel(view, 100, 100, -120, 0)
            tryVerify(() => diff.textOffset > 0, 2000)
        }

        function test_diagonal_swipe_keeps_its_sideways_part() {
            const diff = makeDiff(200)
            const view = list(diff)
            mouseWheel(view, 100, 100, -120, -120)
            tryVerify(() => diff.textOffset > 0 && view.contentY > 0, 2000)
        }

        function test_sideways_offset_stays_within_the_text() {
            const diff = makeDiff(60)
            diff.scrollText(-1e6)
            compare(diff.textOffset, diff.maximumOffset)
            diff.scrollText(1e6)
            compare(diff.textOffset, 0)
        }
    }
}
