import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import GitLama

// Every GitLama QML file compiles with its imports resolved: a broken import,
// an unknown type or a syntax error in any screen fails here even when no
// other test reaches that file. The native types come from tests/stubs.
TestCase {
    id: componentsCase
    name: "Components"

    FolderListModel {
        id: files
        folder: Qt.resolvedUrl("../GitLama/")
        nameFilters: ["*.qml"]
        showDirs: false
    }

    function test_every_file_compiles() {
        tryCompare(files, "status", FolderListModel.Ready)
        verify(files.count > 100, "found " + files.count + " QML files")
        const failures = []
        for (let i = 0; i < files.count; ++i) {
            const name = files.get(i, "fileName")
            // Singletons are types, not components; the import above loads them.
            const component = Qt.createComponent(files.get(i, "fileUrl"), Component.PreferSynchronous)
            if (component.status === Component.Error)
                failures.push(name + ": " + component.errorString())
        }
        compare(failures.join("\n"), "")
    }
}
