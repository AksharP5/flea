// Run with node tests/menu-dialog-check.js; exercise the QML reply handler against real asynchronous orderings.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../ui/MenuActionDialog.qml'), 'utf8');
const receive = source.match(/^    function receive\(message\) \{([\s\S]*?)^    \}/m);
assert.ok(receive, 'the production reply handler must be present');

function dialog() {
    const events = [];
    const state = {opened: false, action: 'deletePermanently', committing: true, busy: true, requestId: 3,
        facts: {count: 2}, checkPending: false, errorText: '', confirmation: {close() { events.push('hide'); }, open() { events.push('show'); }},
        closeFocus: {forceActiveFocus() { events.push('focus-cancel'); }},
        refreshDeletion() { events.push('refresh'); }, checkDeletion() { events.push('check'); },
        deleted(message) { events.push(message); }, finish() { events.push('finish'); }, events};
    Object.defineProperty(state, 'deletionActive', {get() { return this.action === 'deletePermanently' && this.committing; }});
    // Production reads root.ownedOps; the harness names the same list through root.
    state.ownedOps = ["properties", "prepareDelete", "refreshDelete", "checkDelete", "delete", "validate", "newFile", ""];
    state.root = state;
    vm.createContext(state);
    vm.runInContext('function receive(message) {' + receive[1] + '\n}', state);
    return state;
}

const deleting = dialog();
deleting.receive({id: 3, op: 'checkDelete', ok: true, valid: true});
assert.equal(deleting.committing, true, 'an earlier check reply cannot clear the active delete');
deleting.receive({id: 3, op: 'delete', ok: true, deleted: 1, failed: 1, remaining: ['/fixture/survivor']});
assert.equal(deleting.events[0].count, 2);
assert.equal(deleting.events[0].deleted, 1);
assert.equal(deleting.events[1], 'finish');

const stale = dialog();
stale.receive({id: 3, op: 'delete', ok: true, stale: true});
assert.deepEqual(stale.events, ['refresh'], 'stale identities require a fresh confirmation before mutation');

const failed = dialog();
failed.receive({id: 3, op: 'delete', ok: false, error: 'backend stopped'});
assert.equal(failed.opened, true);
assert.equal(failed.committing, false);
assert.equal(failed.errorText, 'backend stopped');
assert.deepEqual(failed.events, ['hide', 'focus-cancel']);

const cancelled = dialog();
cancelled.committing = false;
cancelled.receive({id: 3, op: 'prepareDelete', ok: true, token: 19});
assert.deepEqual(cancelled.events, [], 'closing before preparation finishes cannot reopen the strip');
const changedWhileChecking = dialog();
changedWhileChecking.opened = true;
changedWhileChecking.committing = false;
changedWhileChecking.checkPending = true;
changedWhileChecking.receive({id: 3, op: 'checkDelete', ok: true, valid: true});
assert.deepEqual(changedWhileChecking.events, ['refresh'], 'a hidden stale strip must be replaced after a pending filesystem change');
const newer = dialog();
newer.receive({id: 2, op: 'delete', ok: false, error: 'old operation'});
assert.equal(newer.committing, true);
assert.deepEqual(newer.events, []);
const menuSource = fs.readFileSync(path.join(__dirname, '../ui/PaneMenuActions.qml'), 'utf8');
const activate = menuSource.match(/^    function activate\(action, selected\) \{([\s\S]*?)^    \}/m);
assert.ok(activate, 'the production menu activation gate must be present');
let requested = 0;
const activation = vm.createContext({pane: {menuSelectionIdentity: 'current'}, identity: 'current', requestId: 3,
    ready: true, activationUsed: false, deleting: false, survivorId: 0, validateActivation() { requested++; }});
vm.runInContext('function activate(action, selected) {' + activate[1] + '\n}', activation);
activation.activate('duplicate', true);
activation.activate('duplicate', true);
assert.equal(requested, 1, 'repeated activation consumes one menu snapshot only once');
assert.equal(activation.activationUsed, true);
console.log('menu dialog: 17 checks, 0 failed');
const COUNT_SINGLE = 1;
const COUNT_MULTI = 2;
// Single-item snapshots discover; multi-item ones never ask.
// Sample input: {"t":"menuaction","id":7,"op":"snapshot","ok":true,"count":1}
const menuResult = menuSource.match(/^        function onMenuResult\(message\) \{([\s\S]*?)^        \}/m);
assert.ok(menuResult, 'the production snapshot reply handler must be present');
function snapshotSends(count, opts) {
    const sends = [];
    const menu = { opened: opts.opened !== false, hasRow: opts.hasRow !== false,
        refreshProviderRows() {}, providersSettled() {}, validateChoice() { return true; } };
    const root = { requestId: 7, identity: 'cur', ready: false, pendingAction: '',
        pendingActivation: false, providersRefreshing: false, launchingId: 0,
        openWithApps: [], openWithLoaded: false, item: null,
        finishProviders() {}, providersFinished() {}, validateActivation() {}, show() {},
        pane: { menuSelectionIdentity: opts.identity || 'cur', message() {},
            contextMenu() { return menu; }, backend: { send(m) { sends.push(m); } } } };
    const ctx = vm.createContext({ root });
    vm.runInContext('function onMenuResult(message) {' + menuResult[1] + '\n}', ctx);
    ctx.onMenuResult({ id: opts.stale === true ? 8 : 7, op: 'snapshot', ok: true, count });
    return sends.filter((m) => m.op === 'applications');
}
assert.equal(snapshotSends(COUNT_SINGLE, {}).length, 1, 'count1 asks applications once');
assert.equal(snapshotSends(COUNT_MULTI, {}).length, 0, 'count2 never asks applications');
assert.equal(snapshotSends(COUNT_SINGLE, { opened: false }).length, 0, 'closed menu never asks');
assert.equal(snapshotSends(COUNT_SINGLE, { stale: true }).length, 0, 'stale id never asks');
assert.equal(snapshotSends(COUNT_SINGLE, { identity: 'other' }).length, 0, 'identity mismatch never asks');
console.log('menu snapshot: 5 checks, 0 failed');

// Sample input: stepFocus(false) then stepFocus(true) over the visible controls.
const stepFocus = source.match(/^    function stepFocus\(back\) \{([\s\S]*?)^    \}/m);
assert.ok(stepFocus, 'the production focus handler must be present');
let focusChecks = 1;
// appList left this dialog in efd8c05c; OpenWithDialog owns that list now.
const FOCUS_BLOCKS = ['root', 'field', 'closeFocus', 'submitFocus'];
const QT_SHIFT = 0x04000000; // Real Qt.ShiftModifier value, carried by the mock.
function controlBlock(name) {
    // Line-anchored: a bare prefix also matches id: requestId inside a call.
    const re = /^[ \t]*id: ([A-Za-z_][A-Za-z0-9_]*)/mg;
    let m, start = -1, end = source.length;
    while ((m = re.exec(source)) !== null) {
        if (start < 0 && m[1] === name) start = m.index;
        else if (start >= 0) { end = m.index; break; }
    }
    assert.ok(start >= 0, name + ' names a real control');
    return source.slice(start, end);
}
function tabBody(block) {
    const handler = block.match(/Keys\.onTabPressed:\s*function\(event\)\s*\{([\s\S]*?)\}/);
    assert.ok(handler, 'a Tab handler must be present');
    return handler[1];
}
function backCall(block) {
    const handler = block.match(/Keys\.onBacktabPressed:\s*([^\n]+)/);
    assert.ok(handler, 'a Backtab handler must be present');
    return handler[1];
}
function drivePolarity(name) {
    const block = controlBlock(name);
    const ctx = { calls: [], Qt: { ShiftModifier: QT_SHIFT }, root: null };
    ctx.root = { stepFocus(back) { ctx.calls.push(back); } };
    vm.createContext(ctx);
    vm.runInContext('function onTab(event) {' + tabBody(block) + '\n}', ctx);
    ctx.onTab({ modifiers: 0, accepted: false });
    assert.equal(ctx.calls.pop(), false, name + ' plain Tab steps forward');
    focusChecks++;
    ctx.onTab({ modifiers: QT_SHIFT, accepted: false });
    assert.equal(ctx.calls.pop(), true, name + ' Shift+Tab steps back');
    focusChecks++;
    const call = backCall(block);
    if (call.indexOf('function') === 0) vm.runInContext('(' + call + ')({modifiers: 0})', ctx);
    else vm.runInContext('(' + call + ')', ctx);
    assert.equal(ctx.calls.pop(), true, name + ' Backtab steps back');
    focusChecks++;
}
for (const name of FOCUS_BLOCKS) drivePolarity(name);
const controls = {};
for (const name of ['field', 'closeFocus', 'submitFocus']) {
    controls[name] = {visible: false, enabled: true, activeFocusOnTab: true, activeFocus: false,
        forceActiveFocus() {
            for (const item of Object.values(controls)) item.activeFocus = false;
            this.activeFocus = true;
        }};
}
vm.createContext(controls);
vm.runInContext('function stepFocus(back) {' + stepFocus[1] + '\n}', controls);
function focused(expected, label) {
    assert.equal(Object.keys(controls).find(name => controls[name].activeFocus), expected, label);
    focusChecks++;
}
controls.closeFocus.visible = true;
controls.stepFocus(false);
focused('closeFocus', 'Properties enters its only visible control');
controls.stepFocus(false);
focused('closeFocus', 'Properties Tab wraps within Close');
controls.stepFocus(true);
focused('closeFocus', 'Properties Shift+Tab wraps within Close');
controls.field.visible = true;
controls.submitFocus.visible = true;
controls.stepFocus(false);
focused('submitFocus', 'an available input action follows Cancel');
controls.stepFocus(false);
focused('field', 'input action wraps to its field');
controls.field.enabled = false;
controls.submitFocus.activeFocusOnTab = false;
controls.stepFocus(true);
focused('closeFocus', 'busy or unavailable controls cannot receive focus');
controls.closeFocus.activeFocus = false;
controls.field.enabled = true;
controls.submitFocus.activeFocusOnTab = true;
controls.stepFocus(true);
focused('submitFocus', 'reverse entry without a current target reaches the last control');
controls.stepFocus(true);
focused('closeFocus', 'reverse steps back into Close');
console.log('menu focus: ' + focusChecks + ' checks, 0 failed');
