const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../plugin/ListSync.js'), 'utf8').replace(/^\.pragma library\s*/, '');
const logic = vm.createContext({});
vm.runInContext(source, logic);
class Model {
 constructor() { this.rows = []; this.operations = 0; }
 get count() { return this.rows.length; }
 get(i) { return this.rows[i]; }
 insert(i, r) { this.rows.splice(i, 0, r); this.operations++; }
 move(from, to) { this.rows.splice(to, 0, this.rows.splice(from, 1)[0]); this.operations++; }
 setProperty(i, name, value) { this.rows[i][name] = value; this.operations++; }
 remove(i, count) { this.rows.splice(i, count); this.operations++; }
}
const row = (id, status = 'running') => ({id, name: id, status});
test('unchanged polling makes no model changes and retains selection', () => {
 const m = new Model(); const rows = [row('a'), row('b'), row('c')];
 logic.sync(m, rows, '', 0); const focused = m.get(1); m.operations = 0;
 assert.equal(logic.sync(m, structuredClone(rows), logic.rowKey(rows[1]), 1), 1);
 assert.equal(m.operations, 0); assert.equal(m.get(1), focused);
});
test('a status update keeps the selected delegate', () => {
 const m = new Model(); logic.sync(m, [row('a'), row('b')], '', 0);
 const focused = m.get(1); m.operations = 0;
 assert.equal(logic.sync(m, [row('a'), row('b', 'stopped')], 'container:b', 1), 1);
 assert.equal(m.get(1), focused); assert.equal(m.get(1).rowData.status, 'stopped');
 assert.equal(m.operations, 1);
});
test('insertion and reordering follow the selected identity', () => {
 const m = new Model(); logic.sync(m, [row('a'), row('b')], '', 0);
 const focused = m.get(1);
 assert.equal(logic.sync(m, [row('x'), row('b'), row('a')], 'container:b', 1), 1);
 assert.equal(m.get(1), focused);
 assert.equal(logic.sync(m, [row('b'), row('x'), row('a')], 'container:b', 1), 0);
 assert.equal(m.get(0), focused);
});
test('removed selection falls back to the nearest remaining row', () => {
 const m = new Model(); logic.sync(m, [row('a'), row('b'), row('c')], '', 0);
 assert.equal(logic.sync(m, [row('a'), row('c')], 'container:b', 1), 1);
 assert.equal(m.count, 2);
 assert.equal(logic.sync(m, [], 'container:c', 1), -1);
});
test('process identity differentiates a reused PID', () => {
 const a = {pid: '42', identity: '100', port: 3000, detail: 'localhost:3000'};
 assert.notEqual(logic.rowKey(a), logic.rowKey({...a, identity: '101'}));
});
