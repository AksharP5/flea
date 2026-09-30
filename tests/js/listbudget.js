// List.qml floors the visible name budget once per view state; Row.qml floors nothing for an assigned row.
.import "sourcefixture.js" as Source

// The full declaration line for one property head, so a renamed or retyped line fails loudly.
// Sample input: lineOf("a\n    readonly property int x: 1\nb", "readonly property int x:") answers the x line.
function lineOf(src, head) {
    var lines = String(src).split("\n")
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].replace(/^\s+/, "").indexOf(head) === 0) return lines[i]
    }
    return ""
}

function run(check) {
    var row = Source.source("ui/Row.qml")
    var list = Source.source("ui/List.qml")
    // The contract: List floors once per view state, and the delegate hands that one budget down.
    check("List computes a plain budget once", list.indexOf("readonly property int nameBudgetPlain") >= 0, true)
    check("List computes a clip budget once", list.indexOf("readonly property int nameBudgetClip") >= 0, true)
    check("the delegate hands the shared budget down", list.indexOf("assignedNameBudget: cell.clipMark.length > 0 ? root.nameBudgetClip : root.nameBudgetPlain") >= 0, true)
    // Row's ordinary path is the assignment: a per-delegate floor here drops this branch and goes red.
    var budget = lineOf(row, "readonly property int nameBudget:")
    check("Row still declares the shared name budget", budget.length > 0, true)
    check("its ordinary path reads the List assignment", budget.indexOf("assignedNameBudget") >= 0, true)
    check("its ordinary path floors nothing", budget.indexOf("Math.floor") < 0, true)
    // Laziness is structural: a property floors on every width change, a function only when the fallback calls it.
    check("Row keeps no eager local budget property", row.indexOf("property int localNameBudget") < 0, true)
    check("the fallback stays a function", row.indexOf("function localNameBudget()") >= 0, true)
    check("drop targets keep their measured fallback", budget.indexOf("root.dropTarget ? root.localNameBudget()") >= 0, true)
    check("unassigned rows keep theirs", budget.indexOf("root.localNameBudget())") >= 0, true)
}
