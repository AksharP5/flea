.import "../../ui/js/Buttons.js" as Buttons
.import "../../ui/js/Collide.js" as Collide

// Variant A (Buttons040, GM 2026-09-24): one 30 px control at body 14, fixed primary per dialog, destructive as error ink, disabled 0.55.

function run(check) {
    // One geometry for every dialog, card and picker button; the label follows Theme.font.body.
    check("every button is 30 tall", Buttons.HEIGHT, 30)
    check("one pad", Buttons.PAD, 9)
    check("one gap", Buttons.GAP, 9)
    check("the ring is its own signal", Buttons.RING, 2)
    check("a disabled control dims", Buttons.DISABLED_OPACITY, 0.55)
    check("hover is 8 percent of the ink", Buttons.WASH_HOVER, 0.08)
    check("press is 14 percent of the ink", Buttons.WASH_PRESS, 0.14)
    // The label follows the body's text stop, so text size moves the buttons with the rows.
    check("the label follows the body's text stop", Buttons.labelSizeFor(18), 18)
    check("and falls back to the shipped size without one", Buttons.labelSizeFor(null), Buttons.LABEL_SIZE)

    // The primary is fixed per dialog, the safe or asked-for action.
    check("trash opens on Cancel", Buttons.primaryFor("trash"), "cancel")
    check("collide opens on Keep both", Buttons.primaryFor("collide"), "keep")
    check("open-with opens on Open", Buttons.primaryFor("openWith"), "open")
    check("convert opens on Convert", Buttons.primaryFor("convert"), "convert")
    check("a new file opens on Create", Buttons.primaryFor("newFile"), "create")
    check("move opens on Move", Buttons.primaryFor("moveTo"), "move")
    check("copy opens on Copy", Buttons.primaryFor("copyTo"), "copy")
    check("network opens on its action", Buttons.primaryFor("network"), "action")
    check("permissions opens on Apply", Buttons.primaryFor("permissions"), "apply")
    check("the picker answers with Open", Buttons.primaryFor("picker"), "accept")
    check("an unknown dialog has no primary", Buttons.primaryFor("nope"), "")

    // A destructive action rests as the error label in a muted frame, never primary.
    check("delete is destructive", Buttons.isDestructive("trash", "delete"), true)
    check("cancel is not", Buttons.isDestructive("trash", "cancel"), false)
    check("replace is destructive", Buttons.isDestructive("collide", "replace"), true)
    check("keep both is not", Buttons.isDestructive("collide", "keep"), false)
    check("the picker's replace is destructive", Buttons.isDestructive("picker", "replace"), true)
    check("the picker's save is not", Buttons.isDestructive("picker", "accept"), false)

    // The card's keyboard opening and its primary agree, so Enter is safe.
    check("the card still opens on Keep both", Collide.START, Buttons.primaryFor("collide"))
}
