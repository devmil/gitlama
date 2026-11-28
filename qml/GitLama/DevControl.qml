import QtQuick

// Development only (GITLAMA_DEV_CONTROL=<file>): runs the steps written to the
// control file while the window stays open, for scripted performance checks.
// Steps: any screenshot step (see Store.screenshotStep), `shot:<png>` saves the
// window, `mark:<label>` logs a timestamped marker, `lagProbe:on|off` logs how
// late a 10 ms timer fires (the GUI thread was blocked) and every presented
// frame's size, `dump:<depth>` logs the item tree, `hide:`/`show:<objectName
// or /index/path>` toggles an item. Run with QT_MESSAGE_PATTERN containing
// %{time process} to correlate with Qt's render-loop timing.
Item {
    id: control

    required property Window window
    required property var hooks

    Timer {
        running: true
        repeat: true
        interval: GitLamaLayout.devControlPoll
        onTriggered: {
            const lines = control.hooks.devControlTake().split("\n").filter(line => line.length > 0)
            for (const line of lines)
                control.run(line)
        }
    }

    function run(line) {
        const separator = line.indexOf(":")
        const name = separator < 0 ? line : line.slice(0, separator)
        const argument = separator < 0 ? "" : line.slice(separator + 1)
        if (name === "shot") {
            window.contentItem.grabToImage(result => result.saveToFile(argument))
        } else if (name === "mark") {
            console.log("gitlama-dev-mark", argument)
        } else if (name === "lagProbe") {
            lagProbe.running = argument === "on"
        } else if (name === "dump") {
            _dump(window.contentItem, "", Number(argument))
        } else if (name === "hide" || name === "show") {
            const found = argument.startsWith("/") ? _itemAt(argument) : _find(window.contentItem, argument)
            if (found)
                found.visible = name === "show"
            console.log("gitlama-dev-mark", name + (found ? "-ok" : "-missing"))
        } else {
            Store.screenshotStep(name, argument)
        }
    }

    function _dump(item, path, depth) {
        console.log("gitlama-dev-tree", path || "/", String(item).split("(")[0], item.objectName, item.visible,
                    Math.round(item.width) + "x" + Math.round(item.height), item.children.length)
        if (depth <= 0)
            return
        for (let index = 0; index < item.children.length; ++index)
            _dump(item.children[index], path + "/" + index, depth - 1)
    }

    function _itemAt(path) {
        let item = window.contentItem
        for (const part of path.split("/").filter(part => part.length > 0))
            item = item ? item.children[Number(part)] : null
        return item
    }

    function _find(item, name) {
        if (item.objectName === name)
            return item
        for (let index = 0; index < item.children.length; ++index) {
            const found = _find(item.children[index], name)
            if (found)
                return found
        }
        return null
    }

    Connections {
        target: control.window
        enabled: lagProbe.running
        function onFrameSwapped() { console.log("gitlama-dev-frame", control.window.width, control.window.height) }
    }

    Timer {
        id: lagProbe
        property real last: 0
        interval: GitLamaLayout.devLagProbeInterval
        repeat: true
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now()
            const late = now - last - interval
            if (late >= GitLamaLayout.devLagProbeReport)
                console.log("gitlama-dev-lag", late)
            last = now
        }
    }
}
