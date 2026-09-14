import QtQuick
import qs.Commons
import "." as Flea
import "js/Ops.js" as Ops
import "js/Transfer.js" as Transfer

// The released transfer card remains the pointer cancellation surface above the informational footer.
Item {
    id: root

    // ui/js/Ops.js's transfer, reassigned on every wire line; running false is what hides the card.
    property var transfer: Ops.emptyTransfer()
    property var owner: null
    readonly property var cancelItem: cancelButton
    readonly property alias byteText: byteLine.text
    signal cancelRequested(int id)

    // Everything drawn comes off this sample rather than straight off the wire, because thirty
    // thousand small files change the name faster than it can be read. Idle rather than bound to
    // transfer: a binding would track the wire live until the first tick happened to break it.
    property var shown: Ops.emptyTransfer()
    // About four changes a second, which is what the eye reads. The backend's own byte heartbeat is
    // 150 ms (src/backend/opsreq.rs PROGRESS_EVERY), so a large file loses almost nothing here.
    readonly property int publishMs: 250
    // TransferCard rule 3: the rate is what this card published over the last two seconds, so one
    // slow beat cannot make it jump and a stall reads 0 B/s rather than a stale number.
    readonly property int rateWindowMs: 2000
    property var rateSamples: []
    readonly property real rate: {
        if (root.rateSamples.length < 2)
            return 0
        var first = root.rateSamples[0]
        var last = root.rateSamples[root.rateSamples.length - 1]
        var span = (last.at - first.at) / 1000
        return span > 0 ? Math.max(0, (last.bytes - first.bytes) / span) : 0
    }

    // Set the instant Cancel is pressed. src/backend/copyfile.rs stops the item in flight and
    // removes what it wrote, so this covers only the round trip to transferdone and the beat above.
    property bool cancelling: false

    // The bar's thickness comes off the type scale the way a mark does, so it follows the display
    // text size instead of pinning a pixel.
    readonly property int barHeight: Math.round(Theme.font.caption / 2)
    readonly property real trackOpacity: 0.25
    // The one other popup in this design, ui/ConvertDialog.qml, is 300 design pixels wide; a second
    // popup at a second width would be two languages.
    readonly property int cardWidth: 300

    visible: root.shown.running
    implicitWidth: Theme.space(root.cardWidth)
    implicitHeight: body.implicitHeight + 2 * Theme.spacing.rowPaddingX
    width: root.implicitWidth
    height: root.implicitHeight

    onTransferChanged: {
        // The first sample and the last are published at once; the ones between wait for the beat.
        if (!root.transfer.running || !root.shown.running || root.transfer.id !== root.shown.id) {
            root.publish()
        }
    }
    onOwnerChanged: root.publish()

    Timer {
        interval: root.publishMs
        repeat: true
        running: root.transfer.running
        onTriggered: root.publish()
    }

    // One published sample, and the window the rate is measured over: everything older than two
    // seconds goes except the one sample just past the edge, which is what the span is taken from.
    function publish() {
        var fresh = root.transfer.id !== root.shown.id ? [] : root.rateSamples
        root.shown = root.transfer
        var now = Date.now()
        var next = fresh.concat([{at: now, bytes: Transfer.movedBytes(root.shown)}])
        var keep = 0
        while (keep + 1 < next.length && now - next[keep + 1].at > root.rateWindowMs) {
            keep += 1
        }
        root.rateSamples = next.slice(keep)
    }

    function cancel() {
        if (!root.transfer.running || root.cancelling) return
        root.cancelRequested(root.transfer.id)
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: function(wheel) { wheel.accepted = true }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surface
        border.width: Theme.spacing.hairline
        border.color: Theme.color.muted
        // Mirrors hyprland decoration:rounding, the same as the menu and the convert popup; 0 on a
        // stock box, and the bar inside stays square either way.
        radius: Style.cornerRadius
    }

    Column {
        id: body
        x: Theme.spacing.rowPaddingX
        y: Theme.spacing.rowPaddingX
        width: root.width - 2 * Theme.spacing.rowPaddingX
        spacing: Theme.spacing.gap

        Item {
            width: parent.width
            height: headline.implicitHeight

            // The card is chrome, so its mark is the OEM icon token the chrome bar's own marks
            // take; the status bar's spiral is caption-sized because the bar's own text is.
            Flea.Spinner {
                id: crawl
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.chromeMarkSize
                height: Theme.chromeMarkSize
                color: Theme.color.muted
            }

            Text {
                id: headline
                anchors.left: crawl.right
                anchors.leftMargin: Theme.spacing.gap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Transfer.head(root.shown)
                color: Theme.color.foreground
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
        }

        Text {
            width: parent.width
            text: Transfer.fileLine(root.shown)
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            // The middle goes and the extension stays: the extension is what says what the file is.
            elide: Text.ElideMiddle
        }

        // Square ends, track and fill both: no row or bar in this language rounds. The fill is a
        // sibling of the track and not its child, because opacity multiplies down into children.
        Item {
            width: parent.width
            height: root.barHeight

            Rectangle {
                anchors.fill: parent
                color: Theme.color.muted
                opacity: root.trackOpacity
            }

            Rectangle {
                width: parent.width * Transfer.fraction(root.shown)
                height: parent.height
                color: Theme.color.accent

                // The card publishes four times a second; easing across the gap is what makes the
                // fill read as movement rather than as four steps a second.
                Behavior on width {
                    NumberAnimation { duration: root.publishMs; easing.type: Easing.Linear }
                }
            }
        }

        // TransferCard rule 1: the bar's own caption, the figures the operator is waiting on inked
        // in the foreground and the words between them muted. Rule 4 makes it absent, not blank,
        // until the first byte sample lands, so the card is one row shorter until then.
        Row {
            id: byteLine
            readonly property var parts: Transfer.byteParts(root.shown, root.rate)
            // The drawn line as one string, so a driven case reads what the card says rather than a shot.
            readonly property string text: byteLine.parts.map(function (p) { return p.text }).join("")
            visible: byteLine.parts.length > 0
            height: visible ? implicitHeight : 0

            Repeater {
                model: byteLine.parts

                delegate: Text {
                    required property var modelData
                    text: modelData.text
                    color: modelData.figure ? Theme.color.foreground : Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                }
            }
        }

        Item {
            width: parent.width
            height: cancelButton.height

            // The frame and paddings of ui/DialogButton.qml, which cannot carry the artifact's own
            // x mark; a dingbat is not a mark in this language, so the mark is drawn as a glyph.
            Rectangle {
                id: cancelButton
                visible: !root.cancelling
                enabled: visible
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel transfer"
                Accessible.onPressAction: root.cancel()
                anchors.right: parent.right
                width: 2 * Theme.spacing.gap + mark.width + Theme.spacing.gap + label.implicitWidth
                height: label.implicitHeight + Theme.spacing.gap + 2 * Theme.spacing.hairline
                color: "transparent"
                border.width: Theme.spacing.hairline
                border.color: Theme.color.muted

                Flea.Glyph {
                    id: mark
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing.gap
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.font.caption
                    height: Theme.font.caption
                    name: "x"
                    color: Theme.color.muted
                }

                Text {
                    id: label
                    anchors.left: mark.right
                    anchors.leftMargin: Theme.spacing.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel"
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                    textFormat: Text.PlainText
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.cancel()
                }
            }

            // The cancel is in and the item in flight is being finished rather than torn in half,
            // which is a state the operator has to be able to see rather than infer from a dead button.
            Text {
                visible: root.cancelling
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancelling"
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
            }
        }
    }
}
