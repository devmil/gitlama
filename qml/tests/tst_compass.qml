import QtQuick
import QtTest
import Meridian
import GitLama

// The Compass names running work and its activity wash shows it: tinted while
// work runs, a sweeping band while progress is unknown, a fill to the known
// progress, and a full fill that fades once the work ends.
Item {
    id: root
    width: 600
    height: 120

    Component {
        id: fillComponent
        CompassFill { width: 200; height: 30 }
    }
    Component {
        id: compassComponent
        Compass { repository: "repo"; branch: "main" }
    }

    TestCase {
        name: "Compass"
        when: windowShown

        function cleanup() {
            Theme.reducedMotion = false
        }

        function makeFill() {
            const fill = createTemporaryObject(fillComponent, root)
            verify(fill !== null)
            return fill
        }
        function part(fill, name) {
            const item = findChild(fill, name)
            verify(item !== null, name)
            return item
        }

        function test_idle_wash_is_hidden() {
            const fill = makeFill()
            verify(!fill.visible)
        }

        function test_unknown_progress_tints_and_sweeps() {
            const fill = makeFill()
            fill.active = true
            tryCompare(fill, "opacity", 1)
            verify(fill.visible)
            compare(part(fill, "compassFillRest").width, fill.width)
            compare(part(fill, "compassFillExtent").width, 0)
            tryCompare(part(fill, "compassFillSweep"), "opacity", 1)
        }

        function test_known_progress_fills_to_it() {
            const fill = makeFill()
            fill.progress = 0.5
            fill.active = true
            tryCompare(part(fill, "compassFillExtent"), "width", 100)
            tryCompare(part(fill, "compassFillSweep"), "opacity", 0)
        }

        function test_finished_work_fills_then_fades() {
            const fill = makeFill()
            fill.active = true
            tryCompare(fill, "opacity", 1)
            fill.active = false
            verify(fill.visible, "the wash stays for the finish")
            tryCompare(part(fill, "compassFillExtent"), "width", fill.width)
            tryVerify(() => !fill.visible, 5000, "the wash fades after the finish")
        }

        function test_new_work_after_a_finish_starts_empty() {
            const fill = makeFill()
            fill.active = true
            fill.active = false
            tryCompare(part(fill, "compassFillExtent"), "width", fill.width)
            fill.active = true
            compare(part(fill, "compassFillExtent").width, 0, "no retracting fill")
        }

        function test_reduced_motion_holds_the_finish_without_moving() {
            Theme.reducedMotion = true
            const fill = makeFill()
            fill.progress = 0.25
            fill.active = true
            compare(part(fill, "compassFillExtent").width, 50, "jumps to the progress")
            fill.active = false
            compare(part(fill, "compassFillExtent").width, fill.width, "jumps to full")
            verify(fill.visible, "the finish still shows")
            tryVerify(() => !fill.visible, 5000)
        }

        function test_finish_shows_work_that_never_showed_running() {
            const fill = makeFill()
            fill.finish()
            verify(fill.shown)
            tryCompare(fill, "opacity", 1)
            tryCompare(part(fill, "compassFillExtent"), "width", fill.width)
            tryVerify(() => !fill.visible, 5000, "the wash fades after the finish")
            compare(part(fill, "compassFillExtent").width, 0, "ready for the next work")
        }

        function test_finish_leaves_running_work_alone() {
            const fill = makeFill()
            fill.active = true
            fill.finish()
            verify(fill.indeterminate, "still sweeping")
            compare(part(fill, "compassFillExtent").width, 0)
        }

        function test_reduced_motion_finish_still_shows() {
            Theme.reducedMotion = true
            const fill = makeFill()
            fill.finish()
            verify(fill.visible)
            compare(part(fill, "compassFillExtent").width, fill.width)
            tryVerify(() => !fill.visible, 5000)
        }

        function test_compass_names_running_work() {
            const compass = createTemporaryObject(compassComponent, root)
            verify(compass !== null)
            const operation = findChild(compass, "operationText")
            const state = findChild(compass, "stateRow")
            const fill = findChild(compass, "compassFill")
            verify(!operation.visible)
            verify(state.visible)
            verify(!fill.active)

            compass.operation = "Pull…"
            verify(operation.visible)
            verify(!state.visible)
            compare(operation.text, "Pull…")
            verify(fill.active)
            tryCompare(fill, "opacity", 1)

            compass.operationDetail = "Pull · Receiving objects 40%"
            compare(operation.text, "Pull · Receiving objects 40%")

            compass.operation = ""
            compass.operationDetail = ""
            verify(state.visible)
            verify(!fill.active)
        }

        function test_compass_finish_reaches_its_wash() {
            const compass = createTemporaryObject(compassComponent, root)
            const fill = findChild(compass, "compassFill")
            compass.finish()
            verify(fill.shown)
            tryCompare(fill, "opacity", 1)
        }

        function test_compass_shows_progress_without_a_name() {
            const compass = createTemporaryObject(compassComponent, root)
            compass.activeProgress = true
            compass.progress = 0.5
            const fill = findChild(compass, "compassFill")
            verify(fill.active)
            compare(fill.progress, 0.5)
        }
    }
}
