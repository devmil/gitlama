pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import Meridian

// Chooses a folder on a connected host: the listed folder
// with Up and Home, a path field that follows what is typed (listing its folder filtered by
// the typed name and telling whether the path is a folder), paged entries, and Open (or
// Create here, where a typed path may not exist yet). Answers the `remoteChooseFolder`
// prompt with the folder's path bytes, or null. Paths are arrays of byte values.
MeridianDialog {
    id: dialog

    property int promptId: -1
    property var answerTo: null
    /// Whether the picker still owes its asker an answer.
    property bool answering: false
    property string profileId: ""
    property bool initializing: false
    property int request: 0
    property bool loading: false
    property var page: null
    property var entries: []
    property var failure: null
    /// The typed start of an entry name; the list shows only matching entries.
    property var filter: null
    /// "checking", "folder", "notFolder", "missing" or "" for a typed path.
    property string typedStatus: ""
    property string pathError: ""
    property bool pathAttempted: false
    /// What a request is for: {kind: "load"|"more"|"follow"|"probe", navigation, path, prefix}.
    property var pending: ({})

    readonly property var host: Labels.remoteHost(profileId) ?? ({})
    readonly property var shown: filter === null ? entries : entries.filter(entry => startsWith(entry.name, filter))
    readonly property bool canOpen: !loading && (page !== null || pathField.text.length > 0)

    /// Chooses a folder on `payload.profileId`'s host; `answer(id, bytes | null)` gets it.
    function ask(id, payload, answer) {
        promptId = id
        answerTo = answer
        answering = true
        profileId = payload.profileId
        initializing = payload.purpose === "initialize"
        page = null
        entries = []
        failure = null
        filter = null
        typedStatus = ""
        pathError = ""
        pathAttempted = false
        pathField.text = ""
        open()
        load(null, false, false)
    }
    function finish(value) {
        if (!answering)
            return
        answering = false
        answerTo(promptId, value)
    }

    // Bytes ------------------------------------------------------------------------

    function encode(text) {
        const bytes = []
        for (const character of text) {
            const code = character.codePointAt(0)
            if (code < 0x80) {
                bytes.push(code)
            } else if (code < 0x800) {
                bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f))
            } else if (code < 0x10000) {
                bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
            } else {
                bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
            }
        }
        return bytes
    }
    /// Strict UTF-8 text of `bytes`, or null when they are not text that can be typed.
    function decode(bytes) {
        let text = ""
        let index = 0
        while (index < bytes.length) {
            const byte = bytes[index]
            const length = byte < 0x80 ? 1 : byte >= 0xc2 && byte <= 0xdf ? 2 : byte >= 0xe0 && byte <= 0xef ? 3 : byte >= 0xf0 && byte <= 0xf4 ? 4 : 0
            if (length === 0 || index + length > bytes.length)
                return null
            let code = length === 1 ? byte : byte & (0xff >> (length + 1))
            for (let offset = 1; offset < length; offset += 1) {
                const next = bytes[index + offset]
                if ((next & 0xc0) !== 0x80)
                    return null
                code = (code << 6) | (next & 0x3f)
            }
            if (code < [0, 0, 0x80, 0x800, 0x10000][length] || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) || code < 0x20 || code === 0x7f)
                return null
            text += String.fromCodePoint(code)
            index += length
        }
        return text
    }
    function same(a, b) {
        return a.length === b.length && a.every((byte, index) => byte === b[index])
    }
    function startsWith(name, prefix) {
        return name.length >= prefix.length && prefix.every((byte, index) => name[index] === byte)
    }
    /// `directory` joined with the entry `name`.
    function child(directory, name) {
        const path = directory.slice()
        if (path.length === 0 || path[path.length - 1] !== 0x2f)
            path.push(0x2f)
        return path.concat(name)
    }
    /// A typed path: {path, error} with error "", "notAbsolute" or "invalid".
    function parse(text) {
        if (text.length === 0)
            return { path: null, error: "empty" }
        if (!text.startsWith("/"))
            return { path: null, error: "notAbsolute" }
        const bytes = encode(text)
        if (text.indexOf("\u0000") >= 0 || bytes.length > 16384)
            return { path: null, error: "invalid" }
        return { path: bytes, error: "" }
    }

    // Listing ----------------------------------------------------------------------

    function list(directory, cursor, purpose) {
        request += 1
        const next = Object.assign({}, pending)
        next[request] = purpose
        pending = next
        Store.remote.listDirectory(request, profileId, directory, cursor ?? "")
    }
    /// Lists `directory` (the home without one); a navigation shows it in the path field.
    function load(directory, more, navigation) {
        if (!more)
            followTimer.stop()
        loading = true
        failure = null
        list(more ? page.directory : directory, more ? page.cursor : "", { kind: more ? "more" : "load", navigation: navigation })
    }
    function showInField(directory) {
        const text = decode(directory)
        const typed = text === null ? "" : (text.endsWith("/") ? text : text + "/")
        pathField.text = typed
        pathField.input.cursorPosition = typed.length
        pathError = ""
        pathAttempted = false
        filter = null
        typedStatus = typed.length === 0 ? "" : "folder"
    }
    function typed(text) {
        followTimer.stop()
        const parsed = parse(text)
        pathError = parsed.error === "empty" ? "" : parsed.error
        typedStatus = parsed.path === null ? "" : "checking"
        if (parsed.path === null) {
            filter = null
            return
        }
        followTimer.path = parsed.path
        followTimer.restart()
    }
    /// Lists the folder a typed path is in, filtered by its last segment.
    function follow(path) {
        let slash = path.lastIndexOf(0x2f)
        const directory = slash === 0 ? [0x2f] : path.slice(0, slash)
        const prefix = path.slice(slash + 1)
        if (page === null || !same(page.directory, directory)) {
            loading = true
            list(directory, "", { kind: "follow", path: path, prefix: prefix })
            return
        }
        settleTyped(page, entries, path, prefix, false)
    }
    function settleTyped(listed, listedEntries, path, prefix, fresh) {
        let status = prefix.length === 0 ? "folder" : ""
        if (status.length === 0) {
            const exact = listedEntries.find(entry => same(entry.name, prefix))
            const kind = exact ? exact.kind : null
            status = kind === "directory" ? "folder" : kind === "file" || kind === "other" ? "notFolder"
                : kind === "symlink" ? "" : listed.cursor === null ? "missing" : ""
        }
        page = listed
        entries = listedEntries
        filter = prefix.length === 0 ? null : prefix
        loading = status.length === 0
        failure = null
        typedStatus = status.length === 0 ? "checking" : status
        if (fresh)
            entryList.positionViewAtBeginning()
        if (status.length === 0)
            list(path, "", { kind: "probe" })
    }
    Connections {
        target: Store.remote
        function onDirectoryListed(requestId, listed, listFailure) {
            const purpose = dialog.pending[requestId]
            if (purpose === undefined)
                return
            const next = Object.assign({}, dialog.pending)
            delete next[requestId]
            dialog.pending = next
            // Only the newest request may change what the picker shows.
            if (requestId !== dialog.request)
                return
            switch (purpose.kind) {
            case "probe":
                dialog.loading = false
                dialog.typedStatus = listed ? "folder"
                    : listFailure && listFailure.code === "notDirectory" ? "notFolder" : "missing"
                return
            case "follow":
                if (!listed) {
                    const absent = listFailure && (listFailure.code === "pathNotFound" || listFailure.code === "notDirectory")
                    dialog.loading = false
                    dialog.filter = null
                    dialog.typedStatus = absent ? "missing" : ""
                    if (!absent)
                        dialog.failure = listFailure
                    return
                }
                dialog.settleTyped(listed, listed.entries, purpose.path, purpose.prefix, true)
                return
            default:
                dialog.loading = false
                if (!listed) {
                    dialog.failure = listFailure
                    return
                }
                dialog.page = listed
                dialog.entries = purpose.kind === "more" ? dialog.entries.concat(listed.entries) : listed.entries
                if (purpose.navigation)
                    dialog.showInField(listed.directory)
                // A newly listed folder starts at its top; more entries keep the place.
                if (purpose.kind !== "more")
                    entryList.positionViewAtBeginning()
            }
        }
    }
    Timer {
        id: followTimer
        property var path: null
        interval: GitLamaLayout.remotePathFollowDelay
        onTriggered: dialog.follow(path)
    }

    function goToTyped() {
        const parsed = parse(pathField.text)
        pathAttempted = true
        pathError = parsed.error === "empty" ? "" : parsed.error
        if (parsed.path !== null)
            load(parsed.path, false, true)
    }
    function choose() {
        followTimer.stop()
        if (pathField.text.length > 0) {
            const parsed = parse(pathField.text)
            pathAttempted = true
            pathError = parsed.error === "empty" ? "" : parsed.error
            if (parsed.path === null)
                return
            // A trailing separator names the same folder.
            let end = parsed.path.length
            while (end > 1 && parsed.path[end - 1] === 0x2f)
                end -= 1
            finish(parsed.path.slice(0, end))
            close()
            return
        }
        if (page !== null) {
            finish(page.directory)
            close()
        }
    }
    function entryIcon(entry) {
        switch (entry.kind) {
        case "directory": return entry.repository ? "folder-git-2" : "folder"
        case "symlink": return "folder-symlink"
        default: return "file"
        }
    }
    function entryKind(entry) {
        switch (entry.kind) {
        case "directory": return entry.repository ? L10n.t("remoteEntryRepository") : ""
        case "symlink": return L10n.t("remoteEntrySymlink")
        case "file": return L10n.t("remoteEntryFile")
        default: return L10n.t("remoteEntryOther")
        }
    }
    readonly property string pathErrorText: !pathAttempted && pathField.text.length === 0 ? ""
        : pathError === "notAbsolute" ? L10n.t("remotePathAbsoluteRequired")
        : pathError === "invalid" ? L10n.t("remotePathInvalid") : ""
    readonly property string typedMessage: {
        const status = pathError.length === 0 ? typedStatus : ""
        switch (status) {
        case "folder": return L10n.t("remotePathFolder")
        case "notFolder": return L10n.t("remotePathNotFolder")
        case "missing": return initializing ? L10n.t("remoteInitializePathNew") : L10n.t("remotePathMissing")
        default: return initializing ? L10n.t("remoteInitializePathHelp") : L10n.t("remoteDirectoryPathHelp")
        }
    }

    widthClass: MeridianDialog.Workflow
    title: initializing ? L10n.tn("remoteInitializeDirectoryTitle", { host: host.label ?? "" })
        : L10n.tn("remoteDirectoryTitle", { host: host.label ?? "" })
    submitDisabled: !canOpen
    onSubmitted: choose()
    onClosed: {
        followTimer.stop()
        request += 1
        finish(null)
    }

    Column {
        width: parent ? parent.width : 0
        spacing: 0

        Row {
            width: parent.width
            spacing: Theme.space.s1
            MeridianIconButton {
                objectName: "remote-directory-up"
                text: L10n.t("remoteDirectoryUp")
                iconName: "arrow-up"
                enabled: dialog.page !== null && dialog.page.parent !== null
                onClicked: dialog.load(dialog.page.parent, false, true)
            }
            MeridianIconButton {
                objectName: "remote-directory-home"
                text: L10n.t("remoteDirectoryHome")
                iconName: "house"
                onClicked: dialog.load(null, false, true)
            }
            Item { width: Theme.space.s2; height: 1 }
            MeridianText {
                objectName: "remote-directory-current"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (busy.visible ? busy.width + Theme.space.s2 : 0)
                role: MeridianText.Code
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                text: dialog.page ? dialog.page.display : L10n.t("remoteDirectoryLoading")
                Accessible.name: L10n.t("remoteDirectoryCurrent")
                Accessible.description: dialog.page ? dialog.page.display : ""
            }
            MeridianSpinner {
                id: busy
                anchors.verticalCenter: parent.verticalCenter
                visible: dialog.loading
            }
        }
        Item { width: 1; height: Theme.space.s4 }
        RemoteField {
            id: pathField
            objectName: "remote-directory-path"
            width: parent.width
            label: L10n.t("remoteDirectoryPath")
            placeholderText: L10n.t("remoteDirectoryPathPlaceholder")
            monospace: true
            error: dialog.pathErrorText
            message: dialog.typedMessage
            onEdited: dialog.typed(text)
            onSubmitted: dialog.goToTyped()
            trailingContent: [
                MeridianSpinner {
                    objectName: "remote-directory-path-checking"
                    visible: dialog.pathError.length === 0 && dialog.typedStatus === "checking"
                    size: Theme.size.iconSmall
                    Accessible.name: L10n.t("remotePathChecking")
                },
                MeridianIcon {
                    readonly property string status: dialog.pathError.length === 0 ? dialog.typedStatus : ""
                    visible: status.length > 0 && status !== "checking"
                    objectName: "remote-directory-path-" + status
                    iconSize: MeridianIcon.Small
                    name: status === "folder" ? "circle-check" : status === "notFolder" ? "circle-alert"
                        : dialog.initializing ? "folder-plus" : "circle-x"
                    color: status === "folder" || (status === "missing" && dialog.initializing) ? Theme.colors.success
                        : status === "notFolder" ? Theme.colors.warning : Theme.colors.danger
                    Accessible.role: Accessible.StaticText
                    Accessible.name: dialog.typedMessage
                }
            ]
        }
        Item { visible: dialog.failure !== null; width: 1; height: Theme.space.s4 }
        MeridianBanner {
            objectName: "remote-directory-failure"
            visible: dialog.failure !== null
            width: parent.width
            tone: MeridianBanner.Error
            message: Labels.remoteFailure(dialog.failure)
            MeridianButton {
                objectName: "remote-directory-refresh"
                visible: dialog.failure !== null && dialog.failure.code === "directoryChanged"
                text: L10n.t("remoteDirectoryRefresh")
                controlSize: MeridianButton.Small
                onClicked: dialog.load(dialog.page ? dialog.page.directory : null, false, false)
            }
            MeridianButton {
                objectName: "remote-directory-restart"
                visible: dialog.failure !== null && dialog.failure.code === "cursorExpired"
                text: L10n.t("remoteDirectoryRestart")
                controlSize: MeridianButton.Small
                onClicked: dialog.load(dialog.page ? dialog.page.directory : null, false, false)
            }
        }
        Item { visible: dialog.page !== null && dialog.page.truncated; width: 1; height: Theme.space.s4 }
        MeridianBanner {
            objectName: "remote-directory-truncated"
            visible: dialog.page !== null && dialog.page.truncated
            width: parent.width
            tone: MeridianBanner.Info
            message: L10n.t("remoteDirectoryTruncated")
        }
        Item { width: 1; height: Theme.space.s4 }
        Item {
            width: parent.width
            height: GitLamaLayout.remoteDirectoryListHeight

            MeridianSpinner {
                anchors.centerIn: parent
                visible: dialog.page === null && dialog.loading
            }
            MeridianText {
                anchors.centerIn: parent
                visible: dialog.page === null && !dialog.loading
                text: L10n.t("remoteDirectoryUnavailable")
            }
            MeridianEmptyState {
                anchors.fill: parent
                visible: dialog.page !== null && dialog.shown.length === 0 && dialog.page.cursor === null
                compact: true
                title: dialog.filter === null ? L10n.t("remoteDirectoryEmpty") : L10n.t("remoteDirectoryNoMatch")
            }
            ListView {
                id: entryList
                objectName: "remote-directory-entries"
                anchors.fill: parent
                visible: dialog.page !== null && (dialog.shown.length > 0 || dialog.page.cursor !== null)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: dialog.shown
                delegate: MeridianListRow {
                    id: entryRow
                    required property var modelData
                    readonly property bool navigable: modelData.kind === "directory" || modelData.kind === "symlink"
                    width: ListView.view.width
                    text: modelData.display
                    meta: dialog.entryKind(modelData)
                    dimmed: !navigable
                    enabled: navigable
                    leading: Component { MeridianIcon { name: dialog.entryIcon(entryRow.modelData) } }
                    Accessible.name: meta.length > 0 ? modelData.display + ", " + meta : modelData.display
                    onClicked: if (navigable && dialog.page) dialog.load(dialog.child(dialog.page.directory, modelData.name), false, true)
                }
                footer: Item {
                    visible: dialog.page !== null && dialog.page.cursor !== null
                    width: ListView.view ? ListView.view.width : 0
                    height: visible ? more.height + 2 * Theme.space.s3 : 0
                    MeridianButton {
                        id: more
                        objectName: "remote-directory-more"
                        x: Theme.space.s3
                        y: Theme.space.s3
                        text: L10n.t("remoteDirectoryLoadMore")
                        controlSize: MeridianButton.Small
                        enabled: !dialog.loading
                        onClicked: dialog.load(null, true, false)
                    }
                }
                C.ScrollBar.vertical: MeridianScrollBar {}
            }
        }
    }
    actions: [
        MeridianButton { text: L10n.t("cancel"); variant: MeridianButton.Quiet; onClicked: dialog.close() },
        MeridianButton {
            objectName: "remote-directory-go"
            text: L10n.t("remoteDirectoryGo")
            enabled: pathField.text.length > 0
            onClicked: dialog.goToTyped()
        },
        MeridianButton {
            objectName: "remote-directory-open"
            text: dialog.initializing ? L10n.t("remoteInitializeHere") : L10n.t("remoteDirectoryOpen")
            variant: MeridianButton.Primary
            enabled: dialog.canOpen
            disabledReason: L10n.t("remoteDirectoryOpenDisabled")
            onClicked: dialog.choose()
        }
    ]
}
