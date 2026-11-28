import QtQuick
import QtTest
import Meridian
import GitLama

// Every lama scene loads as an image in both themes, at its size, and an
// unknown scene falls back to the resting one instead of an empty image.
Item {
    id: root
    width: 300
    height: 200

    Component {
        id: sceneComponent
        LamaScene {}
    }

    TestCase {
        name: "LamaScene"
        when: windowShown

        function cleanup() {
            Theme.mode = Theme.Light
        }

        function test_every_scene_loads_data() {
            return [{ tag: "light", dark: false }, { tag: "dark", dark: true }]
        }
        function test_every_scene_loads(data) {
            if (data.dark)
                Theme.mode = Theme.Dark
            for (const scene of ["moved", "renamed", "select", "waiting", "unchanged", "failed"]) {
                const image = createTemporaryObject(sceneComponent, root, { scene: scene })
                tryCompare(image, "status", Image.Ready, 2000, scene)
                compare(image.implicitWidth, GitLamaLayout.lamaSceneWidth)
                verify(image.source.toString().indexOf("%7B") < 0, scene + " left a colour token unfilled")
            }
        }

        function test_unknown_scene_rests() {
            const image = createTemporaryObject(sceneComponent, root, { scene: "nothing" })
            const fallback = createTemporaryObject(sceneComponent, root, { scene: "select" })
            compare(image.source, fallback.source)
        }
    }
}
