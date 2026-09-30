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

// Split one top-level ternary into [condition, true arm, false arm]; anything else answers no parse.
// Sample input: splitTernary("a ? b : c") answers ["a", "b", "c"], splitTernary("f(x)") answers [].
function splitTernary(expr) {
    var text = String(expr), depth = 0, q = -1
    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i)
        if (ch === "(") depth += 1
        else if (ch === ")") depth -= 1
        else if (ch === "?" && depth === 0 && q < 0) q = i
    }
    if (q < 0) return []
    var cond = text.substring(0, q), rest = text.substring(q + 1)
    depth = 0
    var nest = 0
    for (var j = 0; j < rest.length; j++) {
        var c = rest.charAt(j)
        if (c === "(") depth += 1
        else if (c === ")") depth -= 1
        else if (c === "?" && depth === 0) nest += 1
        else if (c === ":" && depth === 0) {
            if (nest === 0) return [cond.trim(), rest.substring(0, j).trim(), rest.substring(j + 1).trim()]
            nest -= 1
        }
    }
    return []
}

// Strip one wrapping paren pair only when it encloses the whole expression.
// Sample input: unparen("(a ? b : c)") answers "a ? b : c", unparen("(a) + (b)") answers "(a) + (b)".
function unparen(expr) {
    var text = String(expr).trim()
    if (text.charAt(0) !== "(" || text.charAt(text.length - 1) !== ")") return text
    var depth = 0
    for (var i = 0; i < text.length; i++) {
        if (text.charAt(i) === "(") depth += 1
        else if (text.charAt(i) === ")") depth -= 1
        if (depth === 0 && i < text.length - 1) return text
    }
    return text.substring(1, text.length - 1).trim()
}

function run(check) {
    var row = Source.source("ui/Row.qml")
    var list = Source.source("ui/List.qml")
    // The contract: List floors once per view state, and the delegate hands that one budget down.
    check("List computes a plain budget once", list.indexOf("readonly property int nameBudgetPlain") >= 0, true)
    check("List computes a clip budget once", list.indexOf("readonly property int nameBudgetClip") >= 0, true)
    check("the delegate hands the shared budget down", list.indexOf("assignedNameBudget: cell.clipMark.length > 0 ? root.nameBudgetClip : root.nameBudgetPlain") >= 0, true)
    // The two-branch shape first: a bare call answers no parse, and every arm below it then goes red too.
    var budget = lineOf(row, "readonly property int nameBudget:")
    check("Row still declares the shared name budget", budget.length > 0, true)
    check("its ordinary path floors nothing", budget.indexOf("Math.floor") < 0, true)
    var outer = splitTernary(budget.substring(budget.indexOf(":") + 1))
    check("the budget branches on drop first", outer.length === 3, true)
    check("the drop test is the drop target", outer.length === 3 && outer[0] === "root.dropTarget", true)
    check("the drop arm calls only the measured fallback", outer.length === 3 && outer[1] === "root.localNameBudget()", true)
    var inner = splitTernary(unparen(outer.length === 3 ? outer[2] : ""))
    check("the inner branch tests the assignment", inner.length === 3 && inner[0] === "root.assignedNameBudget > -2", true)
    check("the assigned arm is the bare assignment", inner.length === 3 && inner[1] === "root.assignedNameBudget", true)
    check("the fallback arm stays measured", inner.length === 3 && inner[2] === "root.localNameBudget()", true)
    // Laziness is structural: a property floors on every width change, a function only when the fallback calls it.
    check("Row keeps no eager local budget property", row.indexOf("property int localNameBudget") < 0, true)
    check("the fallback stays a function", row.indexOf("function localNameBudget()") >= 0, true)
}
