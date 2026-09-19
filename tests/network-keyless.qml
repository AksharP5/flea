//@ pragma ShellId flea-network-keyless-test

import QtQuick
import Quickshell
import Quickshell.Io

// An sftp place is mounted once with no password at all before any credential is demanded, because
// gvfs's sftp backend is the ssh binary and a key or an agent can answer it. Phase 1 proves the
// passwordless open; phase 2 proves a refused one is what asks. tests/network-keyless.sh drives it.
ShellRoot {
    id: root

    property bool finished: false
    property int phase: 0
    property bool authenticatedCompleted: false
    readonly property string authRequestId: "network-keyless-auth"

    function finish(message) {
        if (root.finished)
            return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    NetworkMounts {
        id: network

        onOpened: function (path) {
            if (root.phase === 5) {
                if (path !== "/password-should-open" || !root.authenticatedCompleted) {
                    root.finish("NETWORK_KEYLESS FAIL authenticated-open=" + path
                                + " completed=" + root.authenticatedCompleted)
                    return
                }
                root.phase = 6
                network.openShare("smb://nas.test/", false, "Nas root")
                return
            }
            // Phases 1 and 4 must try the key before any remembered password.
            if (path !== "/key-should-open" || (root.phase !== 1 && root.phase !== 4)) {
                root.finish("NETWORK_KEYLESS FAIL opened=" + path + " phase=" + root.phase)
                return
            }
            if (root.phase === 1) {
                root.phase = 2
                network.openShare("sftp://ask@slot.test/home", false, "Ask slot")
                return
            }
            root.phase = 5
            network.remember("sftp://pw@slot.test/home", "fixture-secret")
            network.openShare("sftp://pw@slot.test/home", false, "Pw slot")
        }

        onCompleted: function (requestId, uri, success, reason) {
            if (root.phase !== 5 || requestId !== root.authRequestId
                    || uri !== "sftp://pw@slot.test/home" || !success || reason !== "") {
                root.finish("NETWORK_KEYLESS FAIL completed=" + requestId + " uri=" + uri
                            + " success=" + success + " reason=" + reason + " phase=" + root.phase)
                return
            }
            root.authenticatedCompleted = true
        }

        // Phase 6: an SMB server root whose info fails but whose list enumerates must still be listed.
        onSharesListed: function (uri, label, names) {
            if (root.phase === 6 && uri === "smb://nas.test/" && names.join(",") === "docs,media")
                root.finish("NETWORK_KEYLESS passwordless=open needs-password=asked bare-root=asked"
                            + " remembered=kept smb-root=listed")
            else
                root.finish("NETWORK_KEYLESS FAIL shares=" + uri + " names=" + names.join(",")
                            + " phase=" + root.phase)
        }

        onRetryRequested: function (uri, label, password, reason, failedConnect) {
            var asked = reason === "Enter the password to mount this location."
                && failedConnect === false
            // Phase 2 is a refused path-shaped place; phase 3 is a refused server root, which the
            // bare-root listing used to claim before the prompt could reach it; phase 5 is a refused
            // place whose password this session already remembered, and it must come back with it;
            // phase 6 is the SMB root and must never reach this signal at all.
            if (root.phase === 2 && asked && password === "" && label === "Ask slot"
                    && uri === "sftp://ask@slot.test/home") {
                root.phase = 3
                network.openShare("sftp://ask@slot.test/", false, "Ask root")
                return
            }
            if (root.phase === 3 && asked && password === "" && label === "Ask root"
                    && uri === "sftp://ask@slot.test/") {
                root.phase = 4
                // A key opens this one even though a password is remembered for it, which is the
                // whole point: the remembered secret is a fallback, not a first resort.
                network.remember("sftp://key@slot.test/home", "fixture-secret")
                network.openShare("sftp://key@slot.test/home", false, "Key slot")
                return
            }
            if (root.phase === 5 && asked && password === "fixture-secret" && label === "Pw slot"
                    && uri === "sftp://pw@slot.test/home") {
                if (root.authenticatedCompleted) {
                    root.finish("NETWORK_KEYLESS FAIL authenticated-retry repeated")
                    return
                }
                // This is the submitted-password route used by the picker and network dialog.
                network.saveLocation(uri, label, password, root.authRequestId)
                return
            }
            root.finish("NETWORK_KEYLESS FAIL retry=" + uri + " reason=" + reason
                        + " password=" + password + " phase=" + root.phase)
        }
    }

    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            root.phase = 1
            network.openShare("sftp://key@slot.test/home", false, "Key slot")
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.finish("NETWORK_KEYLESS FAIL timeout phase=" + root.phase)
    }
}
