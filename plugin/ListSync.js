.pragma library

// Update rows in place so delegates, keyboard focus, and scroll survive polling.
function rowKey(row) {
    if (row.path) return "project:" + row.path;
    if (row.id) return "container:" + row.id;
    return "port:" + (row.pid || "") + ":" + (row.identity || "") + ":" + row.port + ":" + row.detail;
}

function sync(model, rows, selectedKey, fallbackIndex) {
    for (var i = 0; i < rows.length; i++) {
        var key = rowKey(rows[i]);
        var found = -1;
        for (var j = i; j < model.count; j++) {
            if (model.get(j).stableKey === key) { found = j; break; }
        }
        if (found === -1) model.insert(i, {stableKey: key, rowData: rows[i]});
        else if (found !== i) model.move(found, i, 1);
        if (JSON.stringify(model.get(i).rowData) !== JSON.stringify(rows[i])) {
            model.setProperty(i, "rowData", rows[i]);
        }
    }
    if (model.count > rows.length) model.remove(rows.length, model.count - rows.length);
    for (var k = 0; k < rows.length; k++) {
        if (rowKey(rows[k]) === selectedKey) return k;
    }
    return rows.length ? Math.max(0, Math.min(fallbackIndex, rows.length - 1)) : -1;
}
