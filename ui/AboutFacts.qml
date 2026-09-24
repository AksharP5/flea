import QtQuick
import Quickshell
import Quickshell.Io
import "js/SettingsAbout.js" as About

// Installed facts are read only when About is shown; each failed query keeps an explicit unknown.
QtObject {
    id: root
    property bool active: false
    property bool loaded: false
    property var known: ({})
    // What ui/js/SettingsAbout.js reads: the installed facts, with the updater's status and the default's claim beside them.
    readonly property var facts: Object.assign({ update: UpdateCheck.status, handler: DefaultClaim.handler, claim: DefaultClaim.claim }, root.known)
    readonly property string binary: Quickshell.env("FLEA_BIN") || "flea"

    function setFact(key, value) {
        var next = Object.assign({}, root.known)
        next[key] = value
        root.known = next
    }

    onActiveChanged: {
        // About opening is one of the updater's two automatic triggers; ui/js/Update.js decides whether the last answer stands.
        if (root.active) UpdateCheck.checkIfDue()
        if (!root.active || root.loaded) return
        root.loaded = true
        version.running = true
        owner.running = true
        DefaultClaim.read()
    }

    property var versionQuery: Process {
        id: version
        command: [root.binary, "--version"]
        property string answer: ""
        stdout: StdioCollector { onStreamFinished: version.answer = this.text.trim() }
        // Sample output: "0.2.0". src/main.rs prints CARGO_PKG_VERSION and nothing else, so the
        // name is tolerated rather than required: demanding it left the Version row reading
        // "Not reported" on every build Flea has ever shipped.
        onExited: function (code) {
            if (code !== 0) return
            var text = version.answer.indexOf("flea ") === 0 ? version.answer.substring(5) : version.answer
            if (text.length > 0) root.setFact("version", text)
        }
    }
    property var ownerQuery: Process {
        id: owner
        command: ["pacman", "-Qqo", root.binary]
        property string answer: ""
        stdout: StdioCollector { onStreamFinished: owner.answer = this.text.trim() }
        // Sample output: flea
        onExited: function (code) {
            if (code !== 0 || owner.answer.length === 0) {
                root.setFact("source", About.installedFrom("", false))
                root.setFact("package", "Not owned by a package")
                return
            }
            packageVersion.command = ["pacman", "-Qi", owner.answer]
            packageVersion.running = true
        }
    }
    // -Qi rather than -Q: the same query carries the build date, and the Built row had nothing
    // setting it at all, so every box read "Not recorded in this build" whatever it was running.
    // Its Validated By line is the signature src/update.rs tells OPR's flea from a local build by.
    property var packageQuery: Process {
        id: packageVersion
        environment: ({ LC_ALL: "C" })
        property string answer: ""
        stdout: StdioCollector { onStreamFinished: packageVersion.answer = this.text }
        onExited: function (code) {
            // A package pacman cannot describe reads as unsigned, the way src/update.rs reads it.
            var facts = About.packageFacts(code === 0 ? packageVersion.answer : "")
            root.setFact("source", About.installedFrom(owner.answer, facts.signed))
            if (facts.package.length > 0) root.setFact("package", facts.package)
            if (facts.built.length > 0) root.setFact("built", facts.built)
        }
    }
}
