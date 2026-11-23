pragma ComponentBehavior: Bound
import QtQuick
import Meridian

// How to connect a provider (the Dart setup guide): numbered steps, the
// exact values to paste as code, and what needs no secret as a caption;
// the provider's application settings open from here.
MeridianDialog {
    id: dialog

    property var presetLabel: name => name
    property string preset: "github"
    property string authentication: "oauth"
    property string webBase: ""
    signal openUrl(string url)

    readonly property string redirectUri: "http://127.0.0.1:49351/oauth/callback"
    readonly property string host: {
        const match = /^https?:\/\/([^\/:]+)/.exec(webBase)
        return match ? match[1] : ""
    }
    readonly property string server: host.length > 0 ? host : L10n.t("hostingGuideServerPlaceholder")
    readonly property bool gitHub: preset === "github" || preset === "gitHubEnterprise"
    readonly property var steps: {
        if (authentication === "gitHubCli")
            return [{ text: L10n.tn("hostingStepCliSignIn", { tool: L10n.t("hostingGitHubCli") }),
                      code: preset === "github" ? "gh auth login" : "gh auth login --hostname " + server },
                    { text: L10n.tn("hostingStepCliReturn", { action: L10n.t("hostingConnectWithCli") }) }]
        if (authentication === "gitLabCli")
            return [{ text: L10n.tn("hostingStepCliSignIn", { tool: L10n.t("hostingGitLabCli") }),
                      code: preset === "gitlab" ? "glab auth login" : "glab auth login --hostname " + server },
                    { text: L10n.tn("hostingStepCliReturn", { action: L10n.t("hostingConnectWithGitLabCli") }) }]
        const list = []
        if (["gitlabSelfManaged", "forgejo", "gitHubEnterprise"].indexOf(preset) >= 0)
            list.push({ text: L10n.tn("hostingStepEnterServer", { field: L10n.t("hostingWebUrl") }) })
        list.push({ text: L10n.t(({ github: "hostingStepCreateGitHub", gitHubEnterprise: "hostingStepCreateEnterprise",
                                    gitlab: "hostingStepCreateGitLab", gitlabSelfManaged: "hostingStepCreateGitLab",
                                    forgejo: "hostingStepCreateForgejo", codeberg: "hostingStepCreateCodeberg" })[preset]) })
        if (preset === "forgejo" || preset === "codeberg")
            list.push({ text: L10n.t("hostingStepPublicClient") })
        list.push(gitHub ? { text: L10n.t("hostingStepDeviceFlow") } : { text: L10n.t("hostingStepRedirect"), code: redirectUri })
        list.push({ text: L10n.tn(preset === "gitlab" || preset === "gitlabSelfManaged" ? "hostingStepCopyApplicationId" : "hostingStepCopyClientId",
                                  { field: L10n.t("hostingOAuthClientId") }) })
        list.push({ text: L10n.tn(gitHub ? "hostingStepAuthorizeDevice" : "hostingStepAuthorizeBrowser", { action: L10n.t("hostingSaveAuthorize") }) })
        return list
    }
    readonly property string note: authentication !== "oauth" ? L10n.t("hostingGuideCliNote")
        : preset === "forgejo" ? L10n.t("hostingGuideNoSecret") + " " + L10n.t("hostingGuideForgejoNote")
        : preset === "gitHubEnterprise" ? L10n.t("hostingGuideNoSecret") + " " + L10n.t("hostingGuideEnterpriseNote")
        : L10n.t("hostingGuideNoSecret")
    readonly property string settingsUrl: gitHub ? webBase + "/settings/developers"
        : preset === "gitlab" || preset === "gitlabSelfManaged" ? webBase + "/-/user_settings/applications"
        : webBase + "/user/settings/applications"

    function show(preset, authentication, webBase) {
        dialog.preset = preset
        dialog.authentication = authentication
        dialog.webBase = webBase ?? ""
        open()
    }

    objectName: "hosting-setup-guide-dialog"
    widthClass: MeridianDialog.Form
    title: L10n.tn("hostingGuideTitle", { provider: presetLabel(preset) })
    closeLabel: L10n.t("close")

    Column {
        width: parent ? parent.width : 0
        spacing: Theme.space.s6
        Repeater {
            model: dialog.steps
            delegate: Row {
                id: step
                required property var modelData
                required property int index
                width: parent.width
                spacing: Theme.space.s4
                StepNumber { id: number; number: step.index + 1 }
                Column {
                    width: parent.width - number.width - parent.spacing
                    spacing: Theme.space.s3
                    MeridianText { width: parent.width; color: Theme.colors.ink; wrapMode: Text.Wrap; text: step.modelData.text }
                    Rectangle {
                        visible: !!step.modelData.code
                        width: parent.width
                        height: visible ? code.implicitHeight + 2 * Theme.space.s4 : 0
                        radius: Theme.radius.md
                        color: Theme.colors.paneAlt
                        MeridianSelectableText {
                            id: code
                            x: Theme.space.s5
                            y: Theme.space.s4
                            width: parent.width - 2 * Theme.space.s5
                            role: MeridianText.CodeSm
                            text: step.modelData.code ?? ""
                        }
                    }
                }
            }
        }
        MeridianText {
            width: parent.width
            role: MeridianText.Caption
            color: Theme.colors.inkMuted
            wrapMode: Text.Wrap
            text: dialog.note
        }
    }
    actions: [
        MeridianButton {
            visible: dialog.authentication === "oauth" && /^https?:\/\/[^\/]+/.test(dialog.settingsUrl)
            text: L10n.t("hostingGuideOpenSettings")
            iconName: "external-link"
            variant: MeridianButton.Primary
            onClicked: dialog.openUrl(dialog.settingsUrl)
        }
    ]
}
