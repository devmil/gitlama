import QtQuick
import QtTest
import Meridian
import GitLama

// A renamed or moved file names where it came from by what changed: the old
// name for a rename in place, the old folder after the shared ones for a move.
Item {
    id: root
    width: 400
    height: 60

    Component {
        id: rowComponent
        FileRow { width: 400 }
    }

    TestCase {
        name: "Rename"
        when: windowShown

        function test_rename_in_place_names_the_old_name() {
            compare(Labels.renameSource("src/Old.swift", "src/New.swift"), "Old.swift")
            compare(Labels.renameSource("Old.swift", "New.swift"), "Old.swift")
            verify(!Labels.movedFolder("src/Old.swift", "src/New.swift"))
        }

        function test_move_names_the_old_folder_after_the_shared_ones() {
            compare(Labels.renameSource("a/ios/Classes/Session.swift", "a/ios/Sources/vtr/Session.swift"),
                    "…/Classes/")
            compare(Labels.renameSource("lib/Session.swift", "src/Session.swift"), "lib/")
            compare(Labels.renameSource("Session.swift", "src/Session.swift"), "./")
            compare(Labels.renameSource("a/b/Session.swift", "a/Session.swift"), "…/b/")
            verify(Labels.movedFolder("lib/Session.swift", "src/Session.swift"))
        }

        function test_move_and_rename_names_both() {
            compare(Labels.renameSource("a/Classes/Old.swift", "a/Sources/New.swift"), "…/Classes/Old.swift")
        }

        function test_no_move_has_no_source() {
            compare(Labels.renameSource("", "a/File.swift"), "")
            compare(Labels.renameSource("a/File.swift", "a/File.swift"), "")
        }

        function test_row_shows_where_the_file_came_from() {
            const row = createTemporaryObject(rowComponent, root, { path: "Session.swift", status: "R" })
            const source = findChild(row, "fileRowSource")
            verify(!source.visible)
            row.sourceHint = "…/Classes/"
            verify(source.visible)
            verify(source.width > 0)
            verify(row.Accessible.name.indexOf(source.text) > 0, "read out with the name")
            row.folder = true
            verify(!source.visible, "folders were not moved")
        }
    }
}
