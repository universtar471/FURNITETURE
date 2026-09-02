/* Prefab Structure Builder - panel logic.
   All Ruby calls go through call(), which no-ops outside SketchUp so the page
   can still be opened in a browser while working on the layout. */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };
  var bridge = function () { return (typeof sketchup !== 'undefined') ? sketchup : null; };

  function call(name) {
    var sk = bridge();
    if (!sk || typeof sk[name] !== 'function') { return false; }
    try {
      sk[name].apply(sk, Array.prototype.slice.call(arguments, 1));
    } catch (e) {
      console.error('sketchup.' + name, e);
      return false;
    }
    return true;
  }

  function on(id, handler) {
    var el = $(id);
    if (el) { el.addEventListener('click', handler); }
  }

  function esc(value) {
    if (value === null || value === undefined) { return ''; }
    return String(value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function num(value, fallback) {
    var n = Number(value);
    return isFinite(n) ? n : (fallback || 0);
  }

  function fillTable(id, rows, rowHtml, emptyText, colspan) {
    var tb = $(id);
    if (!tb) { return; }
    tb.innerHTML = '';
    rows = rows || [];
    if (!rows.length) {
      tb.innerHTML = '<tr><td class="empty" colspan="' + colspan + '">' + esc(emptyText) + '</td></tr>';
      return;
    }
    rows.forEach(function (r, i) {
      var tr = document.createElement('tr');
      tr.innerHTML = rowHtml(r, i);
      var zoom = tr.querySelector('[data-zoom]');
      if (zoom) {
        zoom.addEventListener('click', function () { call('zoomEntity', Number(zoom.getAttribute('data-zoom'))); });
      }
      tb.appendChild(tr);
    });
  }

  function options(select, values, selected, labeller) {
    if (!select) { return; }
    select.innerHTML = '';
    (values || []).forEach(function (v) {
      var o = document.createElement('option');
      var value = (typeof v === 'object') ? v.value : v;
      o.value = value;
      o.textContent = labeller ? labeller(v) : ((typeof v === 'object') ? v.label : v);
      if (String(value) === String(selected)) { o.selected = true; }
      select.appendChild(o);
    });
  }

  /* ---------------- navigation ---------------- */
  function showPanel(name) {
    var target = $('panel-' + name);
    if (!target) { return; }
    Array.prototype.forEach.call(document.querySelectorAll('.panel'), function (p) { p.classList.remove('active'); });
    Array.prototype.forEach.call(document.querySelectorAll('#rail button'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-panel') === name);
    });
    target.classList.add('active');
  }
  window.showPanel = showPanel;

  Array.prototype.forEach.call(document.querySelectorAll('#rail button'), function (b) {
    b.addEventListener('click', function () { showPanel(b.getAttribute('data-panel')); });
  });

  /* ---------------- shared state ---------------- */
  var PROFILES = ['100x100', '25x25', '50x50', '40x80', '30x60', '50x100', 'I150', 'I200'];
  var columnState = { types: [], levels: [], index: 0, roles: [], materials: [], colors: [] };
  var materialRows = [];
  var projectStatus = {};

  /* ---------------- SOURCE ---------------- */
  window.renderScan = function (rows) {
    rows = rows || [];
    var total = rows.reduce(function (a, r) { return a + num(r.quantity); }, 0);
    var s = $('scanSummary');
    if (s) {
      s.innerHTML = '<b>' + rows.length + '</b> classified type(s), <b>' + total + '</b> placeholder(s).';
    }
    fillTable('scanRows', rows, function (r) {
      return '<td>' + esc(r.type) + '</td>' +
             '<td><b>' + esc(r.name) + '</b></td>' +
             '<td>' + esc(r.source) + '</td>' +
             '<td>' + esc(r.quantity) + '</td>' +
             '<td>' + (r.nested ? '<span class="pill info">NESTED</span>' : '') + '</td>' +
             '<td><button class="mini" data-zoom="' + esc((r.entity_ids || [])[0]) + '">Zoom</button></td>';
    }, 'No semantic source groups found. Name a group COLUMN 1, WALL 1, ROOF 1 and rescan.', 6);
  };

  on('btnScan', function () { call('scan'); });
  on('btnSetupTags', function () { call('setupTags'); });

  /* ---------------- COLUMN ---------------- */
  function currentType() { return columnState.types[columnState.index] || null; }

  function colorForProfile(profile) {
    var hit = (columnState.colors || []).filter(function (c) { return c.profile === profile; })[0];
    return hit || { tag: '', color: '#999999' };
  }

  function renderColumnList() {
    var box = $('columnTypeList');
    if (!box) { return; }
    box.innerHTML = '';
    if (!columnState.types.length) {
      box.innerHTML = '<div class="item empty">No column types.</div>';
      return;
    }
    columnState.types.forEach(function (t, i) {
      var div = document.createElement('div');
      div.className = 'item' + (i === columnState.index ? ' active' : '');
      div.innerHTML = '<b>' + esc(t.name) + '</b><span class="meta">' + esc(t.profile) + ' &bull; ' + esc(t.structural_role) + '</span>';
      div.addEventListener('click', function () { columnState.index = i; renderColumnList(); renderColumnForm(); });
      box.appendChild(div);
    });
  }

  function renderColumnForm() {
    var t = currentType();
    if (!t) { return; }
    var levelNames = columnState.levels.map(function (l) { return l.name; });
    options($('colProfile'), PROFILES, t.profile);
    options($('colMaterial'), columnState.materials, t.material);
    options($('colRole'), columnState.roles, t.structural_role);
    options($('colBaseLevel'), levelNames, t.base_level);
    options($('colTopLevel'), levelNames, t.top_level);
    if ($('colHeightMode')) { $('colHeightMode').value = t.height_mode; }
    if ($('colHeight')) { $('colHeight').value = num(t.height_mm); }
    if ($('colRotation')) { $('colRotation').value = String(num(t.rotation_deg)); }
    if ($('colDescription')) { $('colDescription').value = t.description || ''; }

    var c = colorForProfile(t.profile);
    if ($('colTag')) { $('colTag').value = c.tag; }
    if ($('colSwatch')) { $('colSwatch').style.background = c.color; }
    if ($('colColorText')) { $('colColorText').textContent = c.color; }

    var fixed = (t.height_mode === 'fixed');
    if ($('colHeight')) { $('colHeight').disabled = !fixed; }
    var byLevel = (t.height_mode === 'level');
    if ($('colBaseLevel')) { $('colBaseLevel').disabled = !byLevel; }
    if ($('colTopLevel')) { $('colTopLevel').disabled = !byLevel; }

    var resolved;
    if (t.height_mode === 'fixed') {
      resolved = num(t.height_mm) + ' mm (fixed)';
    } else if (t.height_mode === 'source') {
      resolved = 'From placeholder height, falling back to ' + num(t.height_mm) + ' mm';
    } else {
      var lookup = {};
      columnState.levels.forEach(function (l) { lookup[l.name] = num(l.elevation_mm); });
      var d = num(lookup[t.top_level]) - num(lookup[t.base_level]);
      resolved = (d > 0 ? d : num(t.height_mm)) + ' mm (' + esc(t.base_level) + ' &rarr; ' + esc(t.top_level) + ')';
    }
    if ($('colResolved')) {
      $('colResolved').innerHTML = 'Resolved height: <b>' + resolved + '</b> &bull; rotation ' +
        esc(num(t.rotation_deg)) + '&deg; &bull; Tag <b>' + esc(c.tag) + '</b>';
    }
  }

  function readColumnForm() {
    var t = currentType();
    if (!t) { return; }
    t.profile = $('colProfile') ? $('colProfile').value : t.profile;
    t.material = $('colMaterial') ? $('colMaterial').value : t.material;
    t.height_mode = $('colHeightMode') ? $('colHeightMode').value : t.height_mode;
    t.height_mm = num($('colHeight') ? $('colHeight').value : t.height_mm);
    t.rotation_deg = num($('colRotation') ? $('colRotation').value : t.rotation_deg);
    t.structural_role = $('colRole') ? $('colRole').value : t.structural_role;
    t.base_level = $('colBaseLevel') ? $('colBaseLevel').value : t.base_level;
    t.top_level = $('colTopLevel') ? $('colTopLevel').value : t.top_level;
    t.description = $('colDescription') ? $('colDescription').value : t.description;
  }

  ['colProfile', 'colMaterial', 'colHeightMode', 'colHeight', 'colRotation',
   'colRole', 'colBaseLevel', 'colTopLevel', 'colDescription'].forEach(function (id) {
    var el = $(id);
    if (el) { el.addEventListener('change', function () { readColumnForm(); renderColumnList(); renderColumnForm(); }); }
  });

  function renderLevels() {
    fillTable('levelRows', columnState.levels, function (l, i) {
      return '<td><input data-level-name="' + i + '" value="' + esc(l.name) + '"></td>' +
             '<td><input data-level-elev="' + i + '" type="number" value="' + esc(num(l.elevation_mm)) + '"></td>' +
             '<td><button class="mini danger" data-level-del="' + i + '">Remove</button></td>';
    }, 'No levels.', 3);
    Array.prototype.forEach.call(document.querySelectorAll('[data-level-del]'), function (b) {
      b.addEventListener('click', function () {
        var i = Number(b.getAttribute('data-level-del'));
        if (columnState.levels.length <= 1) { return; }
        columnState.levels.splice(i, 1);
        renderLevels();
      });
    });
  }

  function readLevels() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-level-name]'), function (el) {
      var i = Number(el.getAttribute('data-level-name'));
      if (columnState.levels[i]) { columnState.levels[i].name = el.value; }
    });
    Array.prototype.forEach.call(document.querySelectorAll('[data-level-elev]'), function (el) {
      var i = Number(el.getAttribute('data-level-elev'));
      if (columnState.levels[i]) { columnState.levels[i].elevation_mm = num(el.value); }
    });
  }

  window.renderColumnTypes = function (p) {
    p = p || {};
    columnState.types = p.types || [];
    columnState.levels = p.levels || [];
    columnState.roles = p.roles || [];
    columnState.materials = p.materials || [];
    columnState.colors = p.profile_colors || [];
    if (p.profiles && p.profiles.length) { PROFILES = p.profiles; }
    if (columnState.index >= columnState.types.length) { columnState.index = 0; }
    renderColumnList();
    renderColumnForm();
    renderLevels();
    refreshProfileSelects();
  };

  function refreshProfileSelects() {
    [['floorPrimary', '100x100'], ['floorSecondary', '40x80'],
     ['prj_col', '100x100'], ['prj_open_ext', '40x80'], ['prj_open_int', '50x100'],
     ['prj_floor_p', 'I150'], ['prj_floor_s', '40x80'],
     ['prj_roof_p', '50x100'], ['prj_roof_s', '30x60']].forEach(function (pair) {
      var el = $(pair[0]);
      if (!el) { return; }
      var keep = el.value || pair[1];
      options(el, PROFILES, keep);
    });
    var support = $('matSupport');
    if (support) { options(support, ['25x25', '40x80', '50x100'], support.value || '25x25'); }
  }

  on('btnColNew', function () {
    readColumnForm();
    var base = currentType();
    var copy = base ? JSON.parse(JSON.stringify(base)) : {};
    copy.name = 'COLUMN ' + (columnState.types.length + 1);
    columnState.types.push(copy);
    columnState.index = columnState.types.length - 1;
    renderColumnList();
    renderColumnForm();
  });

  on('btnColDup', function () {
    readColumnForm();
    var t = currentType();
    if (!t) { return; }
    var copy = JSON.parse(JSON.stringify(t));
    copy.name = t.name + ' copy';
    columnState.types.push(copy);
    columnState.index = columnState.types.length - 1;
    renderColumnList();
    renderColumnForm();
  });

  on('btnColRename', function () {
    var t = currentType();
    if (!t) { return; }
    var name = window.prompt('Column type name', t.name);
    if (!name) { return; }
    t.name = name;
    renderColumnList();
    renderColumnForm();
  });

  on('btnColDelete', function () {
    if (columnState.types.length <= 1) {
      window.alert('At least one column type is required.');
      return;
    }
    columnState.types.splice(columnState.index, 1);
    columnState.index = 0;
    renderColumnList();
    renderColumnForm();
  });

  on('btnColSave', function () {
    readColumnForm();
    call('saveColumnTypes', JSON.stringify(columnState.types));
  });

  on('btnColGenerate', function () {
    readColumnForm();
    var t = currentType();
    call('saveColumnTypes', JSON.stringify(columnState.types));
    call('generateColumns', t ? t.name : '');
  });

  on('btnLevelAdd', function () {
    readLevels();
    var last = columnState.levels[columnState.levels.length - 1];
    columnState.levels.push({
      name: 'Level ' + (columnState.levels.length + 1),
      elevation_mm: last ? num(last.elevation_mm) + 3000 : 0
    });
    renderLevels();
  });

  on('btnLevelSave', function () {
    readLevels();
    call('saveLevels', JSON.stringify(columnState.levels));
  });

  /* ---------------- WALL ---------------- */
  on('btnGenerateWalls', function () {
    call('generateWalls', $('wallType').value, $('wallSpacing').value);
  });

  /* ---------------- OPENING ---------------- */
  window.renderOpenings = function (rows) {
    fillTable('openingRows', rows, function (r) {
      var c = r.config || {};
      var isDoor = (r.type === 'door');
      return '<td data-oid="' + esc(r.name) + '"><b>' + esc(r.name) + '</b></td>' +
             '<td>' + esc(r.quantity) + '</td>' +
             '<td><input data-k="width" type="number" value="' + esc(num(c.width)) + '"></td>' +
             '<td><input data-k="height" type="number" value="' + esc(num(c.height)) + '"></td>' +
             '<td><input data-k="sill" type="number" value="' + esc(num(c.sill)) + '"' + (isDoor ? ' disabled' : '') + '></td>' +
             '<td><select data-k="location">' +
               '<option value="exterior"' + (c.location === 'exterior' ? ' selected' : '') + '>Exterior</option>' +
               '<option value="interior"' + (c.location === 'interior' ? ' selected' : '') + '>Interior</option>' +
             '</select></td>' +
             '<td><select data-k="frame">' +
               PROFILES.map(function (p) {
                 return '<option value="' + esc(p) + '"' + (c.frame === p ? ' selected' : '') + '>' + esc(p) + '</option>';
               }).join('') +
             '</select></td>';
    }, 'No DOOR or WINDOW placeholders found.', 7);
  };

  function openingData() {
    var out = {};
    Array.prototype.forEach.call(document.querySelectorAll('#openingRows tr'), function (tr) {
      var idCell = tr.querySelector('[data-oid]');
      if (!idCell) { return; }
      var o = {};
      Array.prototype.forEach.call(tr.querySelectorAll('[data-k]'), function (el) {
        o[el.getAttribute('data-k')] = (el.type === 'number') ? num(el.value) : el.value;
      });
      out[idCell.getAttribute('data-oid')] = o;
    });
    return out;
  }

  on('btnSaveOpenings', function () { call('saveOpenings', JSON.stringify(openingData())); });
  on('btnGenerateOpenings', function () { call('generateOpenings', JSON.stringify(openingData())); });

  /* ---------------- FLOOR ---------------- */
  var FLOOR_PRESETS = {
    GROUND_STEEL_CEMBOARD: ['100x100', '40x80', 500],
    UPPER_DECK: ['I200', 'I150', 1000],
    UPPER_I_CEMBOARD: ['I200', 'I150', 600],
    BALCONY_WPC: ['100x100', '40x80', 500]
  };

  if ($('floorType')) {
    $('floorType').addEventListener('change', function () {
      var p = FLOOR_PRESETS[$('floorType').value];
      if (!p) { return; }
      $('floorPrimary').value = p[0];
      $('floorSecondary').value = p[1];
      $('floorSpacing').value = p[2];
    });
  }

  on('btnGenerateFloor', function () {
    call('generateFloor', $('floorType').value, $('floorPrimary').value,
         $('floorSecondary').value, $('floorSpacing').value, $('floorDirection').value);
  });

  /* ---------------- ROOF ---------------- */
  function roofPreset() {
    var t = $('roofType') ? $('roofType').value : 'MONO';
    if ($('ridgePos')) { $('ridgePos').disabled = (t !== 'GABLE'); }
    if ($('roofHighLabel')) {
      $('roofHighLabel').childNodes[0].nodeValue = (t === 'GABLE') ? 'Ridge height (mm)' : 'High height (mm)';
    }
  }
  if ($('roofType')) { $('roofType').addEventListener('change', roofPreset); }
  roofPreset();

  on('btnGenerateRoof', function () {
    var v = function (id) { return $(id).value; };
    // High and ridge share one input: a mono roof has no separate ridge height.
    call('generateRoof', v('roofType'), v('roofHigh'), v('roofLow'), v('roofHigh'),
         v('ridgePos'), v('roofDirection'), v('ohFront'), v('ohBack'), v('ohLeft'),
         v('ohRight'), v('roofSpacing'), v('roofCover'), $('roofSoffit').checked);
  });

  /* ---------------- MATERIAL ---------------- */
  window.renderMaterials = function (rows) {
    materialRows = rows || [];
    var sel = $('materialPreset');
    if (!sel) { return; }
    var keep = sel.value;
    sel.innerHTML = '';
    materialRows.forEach(function (r) {
      var o = document.createElement('option');
      o.value = r.id;
      o.textContent = r.label || r.id;
      sel.appendChild(o);
    });
    if (keep && materialRows.some(function (r) { return r.id === keep; })) { sel.value = keep; }
    materialChanged();
  };

  function materialChanged() {
    var sel = $('materialPreset');
    if (!sel) { return; }
    var r = materialRows.filter(function (x) { return x.id === sel.value; })[0];
    if (!r) { return; }
    $('matFamily').value = r.family || '';
    $('matW').value = num(r.stock_width);
    $('matL').value = num(r.stock_length);
    $('matT').value = num(r.thickness);
    $('matEff').value = num(r.effective_width || r.stock_width);
    if ($('matSupport')) { $('matSupport').value = r.support_profile || '25x25'; }
    $('matRotate').checked = (r.allow_rotate === true || r.allow_rotate === 'true');
  }
  if ($('materialPreset')) { $('materialPreset').addEventListener('change', materialChanged); }

  on('btnPreviewStock', function () {
    call('previewStock', $('materialPreset').value, $('reqW').value, $('reqL').value);
  });

  window.renderStockPreview = function (p) {
    p = p || {};
    var s = p.stats || {};
    var el = $('stockPreview');
    if (!el) { return; }
    el.innerHTML = '<b>' + esc(p.preset) + '</b><br>' +
      num(s.pieces) + ' piece(s): ' + num(s.full) + ' FULL + ' + num(s.cut) + ' CUT<br>' +
      'Used ' + num(s.used_m2) + ' m&sup2; &bull; purchase envelope ' + num(s.purchase_m2) +
      ' m&sup2; &bull; rectangular waste ' + num(s.waste_m2) + ' m&sup2; (' + num(s.waste_percent) + '%)';
  };

  on('btnCheckStock', function () { call('checkStock'); });

  window.renderStockReport = function (rows) {
    fillTable('stockRows', rows, function (r) {
      var cls = (String(r.status).toUpperCase() === 'ERROR') ? 'error' : 'ok';
      return '<td><button class="mini" data-zoom="' + esc(r.id) + '">' + esc(r.name) + '</button></td>' +
             '<td>' + esc(r.material) + '</td><td>' + esc(r.actual) + '</td><td>' + esc(r.stock) + '</td>' +
             '<td><span class="pill ' + cls + '">' + esc(r.status) + '</span></td>';
    }, 'No stock-controlled sheets generated yet.', 5);
  };

  on('btnSaveMaterial', function () {
    var id = ($('customMatId').value || '').trim();
    if (!id) { window.alert('Enter a preset ID.'); return; }
    call('saveMaterial', id, JSON.stringify({
      label: id,
      family: $('customFamily').value,
      stock_width: num($('matW').value),
      stock_length: num($('matL').value),
      thickness: num($('matT').value),
      effective_width: num($('matEff').value),
      allow_rotate: $('matRotate').checked,
      support_profile: $('matSupport') ? $('matSupport').value : '25x25',
      support_role: 'sheet_joint'
    }));
  });

  /* ---------------- CONNECTION ---------------- */
  var CONNECTION_RULES = [
    { value: 'I_COLUMN_I_BOLTED', label: 'I beam → I column • plate + bolts' },
    { value: 'I_SHS_WELD', label: 'I beam → 100×100 column • direct weld' },
    { value: 'I_SECONDARY_PRIMARY_BOLTED', label: 'Secondary I → Primary I • bolted plate' },
    { value: 'ROOF_SHS_WELD', label: 'Roof 50×100 → 100×100 column • direct weld' },
    { value: 'UPPER_COLUMN_DECK_PLATE', label: 'Upper 100×100 column → deck/I floor • base plate' }
  ];
  options($('connRule'), CONNECTION_RULES, 'I_COLUMN_I_BOLTED');

  on('btnAutoConnections', function () { call('autoConnections', $('connDetail').value); });
  on('btnConnectSelected', function () { call('connectSelected', $('connRule').value, $('connDetail').value); });
  on('btnRefreshConnections', function () { call('getConnections'); });

  window.renderConnections = function (rows) {
    fillTable('connectionRows', rows, function (r) {
      return '<td><button class="mini" data-zoom="' + esc(r.id) + '">' + esc(r.name) + '</button></td>' +
             '<td>' + esc(r.rule) + '</td><td>' + esc(r.member_a) + '</td>' +
             '<td>' + esc(r.member_b) + '</td><td>' + esc(r.detail) + '</td>';
    }, 'No connections generated yet.', 5);
  };

  /* ---------------- TAG ---------------- */
  window.renderTags = function (rows) {
    fillTable('tagRows', rows, function (r) {
      var swatch = r.color ? '<span class="swatch" style="background:' + esc(r.color) + '"></span> ' + esc(r.color) : '&mdash;';
      return '<td><b>' + esc(r.name) + '</b></td>' +
             '<td>' + esc(r.profile || '') + '</td>' +
             '<td>' + swatch + '</td>' +
             '<td>' + (r.exists ? '<span class="pill ok">YES</span>' : '<span class="pill warning">MISSING</span>') + '</td>' +
             '<td>' + (r.exists ? (r.visible ? 'Visible' : 'Hidden') : '') + '</td>';
    }, 'Tags not created yet.', 5);
  };
  on('btnSetupTags2', function () { call('setupTags'); });
  on('btnRefreshTags', function () { call('getTags'); });

  /* ---------------- UPDATE ---------------- */
  window.renderUpdateStatus = function (rows) {
    fillTable('updateRows', rows, function (r) {
      var st = r.changed ? 'CHANGED' : (r.tracked ? 'CLEAN' : 'NEW');
      return '<td><b>' + esc(r.name) + '</b><br><small>' + esc(r.path || '') + '</small></td>' +
             '<td>' + esc(r.type) + '</td><td>' + esc(r.depth) + '</td>' +
             '<td><span class="pill ' + st.toLowerCase() + '">' + st + '</span></td>' +
             '<td><button class="mini" data-zoom="' + esc(r.id) + '">Zoom</button></td>';
    }, 'No semantic source objects.', 5);
  };

  on('btnBaseline', function () { call('trackBaseline'); });
  on('btnUpdateChanged', function () { call('updateChanged'); });
  on('btnUpdateSelected', function () { call('updateSelected'); });
  on('btnRefreshUpdate', function () { call('getUpdateStatus'); });

  /* ---------------- CHECK ---------------- */
  function issueRow(r) {
    return '<td><span class="pill ' + esc(r.severity) + '">' + esc(String(r.severity || 'info').toUpperCase()) + '</span></td>' +
           '<td>' + esc(r.code) + '</td>' +
           '<td><b>' + esc(r.name || '') + '</b></td>' +
           '<td class="wrap">' + esc(r.message) + '<br><small>' + esc(r.fix || '') + '</small></td>' +
           '<td>' + (r.id ? '<button class="mini" data-zoom="' + esc(r.id) + '">Zoom</button>' : '') + '</td>';
  }

  function issueSummary(id, rows) {
    var counts = { error: 0, warning: 0, info: 0 };
    (rows || []).forEach(function (r) { counts[r.severity] = (counts[r.severity] || 0) + 1; });
    var el = $(id);
    if (el) {
      el.innerHTML = '<b>' + (rows || []).length + ' issue(s)</b> &bull; ' +
        counts.error + ' error &bull; ' + counts.warning + ' warning &bull; ' + counts.info + ' info';
    }
  }

  window.renderChecks = function (rows) {
    fillTable('checkRows', rows, issueRow, 'No model-rule issues found.', 5);
    issueSummary('checkSummary', rows);
  };

  on('btnCheckModel', function () { call('checkModel'); });
  on('btnFixChanged', function () { call('updateChanged'); });
  on('btnCheckConnections', function () { call('autoConnections', $('connDetail').value); });

  /* ---------------- BOM ---------------- */
  window.renderBOM = function (p) {
    p = p || {};
    var s = p.summary || {};
    var sum = $('bomSummary');
    if (sum) {
      sum.innerHTML = '<b>' + num(s.items) + ' generated item(s)</b> &bull; steel ' + num(s.steel_length_m) +
        ' m &bull; sheets ' + num(s.sheet_area_m2) + ' m&sup2; &bull; connection parts ' + num(s.connection_parts);
    }
    fillTable('bomRows', p.rows, function (r) {
      return '<td>' + esc(r.category) + '</td><td><b>' + esc(r.item) + '</b></td>' +
             '<td>' + esc(r.system) + '</td><td>' + esc(r.role) + '</td><td>' + esc(r.quantity) + '</td>' +
             '<td>' + (r.total_length_m ? esc(r.total_length_m) + ' m' : '') + '</td>' +
             '<td>' + (r.total_area_m2 ? esc(r.total_area_m2) + ' m&sup2;' : '') + '</td>';
    }, 'No generated BOM items.', 7);
    fillTable('cutRows', p.cut_rows, function (r) {
      return '<td><b>' + esc(r.profile) + '</b></td><td>' + esc(r.length_mm) + ' mm</td>' +
             '<td>' + esc(r.quantity) + '</td><td>' + esc(r.total_length_m) + ' m</td><td>' + esc(r.roles) + '</td>';
    }, 'No steel members.', 5);
    fillTable('stockPlanRows', p.stock_plan, function (r) {
      return '<td><b>' + esc(r.profile) + '</b></td><td>' + esc(r.bars) + '</td><td>' + esc(r.cuts) + '</td>' +
             '<td>' + esc(r.oversize) + '</td><td>' + esc(r.purchase_m) + ' m</td>' +
             '<td>' + esc(r.waste_m) + ' m (' + esc(r.waste_percent) + '%)</td>';
    }, 'No stock plan.', 6);
    fillTable('matSummaryRows', p.materials, function (r) {
      return '<td><b>' + esc(r.material) + '</b></td><td>' + esc(r.preset || '—') + '</td>' +
             '<td>' + esc(r.pieces) + '</td><td>' + esc(r.full) + '/' + esc(r.cut) + '</td>' +
             '<td>' + esc(r.actual_area_m2) + ' m&sup2;</td><td>' + esc(r.min_stock_by_area || '—') + '</td>';
    }, 'No sheet or finish materials.', 6);
  };

  on('btnRefreshBOM', function () { call('getBOM'); });
  on('btnExportBOM', function () { call('exportBOM'); });
  on('btnExportCutList', function () { call('exportCutList'); });

  /* ---------------- PROJECT ---------------- */
  window.renderProject = function (p) {
    p = p || {};
    var c = p.preset || {};
    refreshProfileSelects();
    var set = function (id, v) { var e = $(id); if (e) { e.value = (v === null || v === undefined) ? '' : v; } };
    set('prj_name', c.project_name);
    set('prj_prefix', c.code_prefix);
    set('prj_revision', c.project_revision);
    set('prj_floor_h', c.floor_height_mm);
    set('prj_col', c.default_column);
    set('prj_wall', c.default_wall_system);
    set('prj_open_ext', c.default_opening_ext);
    set('prj_open_int', c.default_opening_int);
    set('prj_stock', c.steel_stock_mm);
    set('prj_kerf', c.steel_kerf_mm);
    set('prj_floor_p', c.default_floor_primary);
    set('prj_floor_s', c.default_floor_secondary);
    set('prj_roof_p', c.default_roof_primary);
    set('prj_roof_s', c.default_roof_secondary);
    var pm = $('prj_preserve_marks');
    if (pm) { pm.checked = (c.preserve_existing_marks !== false); }

    var mc = $('markedCount');
    if (mc) { mc.innerHTML = '<b>' + num(p.marked_count) + '</b> generated object(s) currently carry a mark.'; }

    projectStatus = p.status || {};
    renderProductionStatus();

    fillTable('reportRows', p.report, function (r) {
      return '<td><b>' + esc(r.system) + '</b></td><td>' + esc(r.quantity) + '</td>' +
             '<td>' + esc(r.steel_length_m) + ' m</td><td>' + esc(r.sheet_area_m2) + ' m&sup2;</td>' +
             '<td>' + esc(r.categories) + '</td>';
    }, 'No generated report data.', 5);
  };

  on('btnSavePreset', function () {
    var val = function (id) { var e = $(id); return e ? e.value : ''; };
    call('saveProjectPreset', JSON.stringify({
      project_name: val('prj_name'),
      code_prefix: val('prj_prefix'),
      project_revision: val('prj_revision'),
      preserve_existing_marks: $('prj_preserve_marks').checked,
      floor_height_mm: num(val('prj_floor_h')),
      default_column: val('prj_col'),
      default_wall_system: val('prj_wall'),
      default_opening_ext: val('prj_open_ext'),
      default_opening_int: val('prj_open_int'),
      default_floor_primary: val('prj_floor_p'),
      default_floor_secondary: val('prj_floor_s'),
      default_roof_primary: val('prj_roof_p'),
      default_roof_secondary: val('prj_roof_s'),
      steel_stock_mm: num(val('prj_stock')),
      steel_kerf_mm: num(val('prj_kerf'))
    }));
  });

  on('btnSavePresetFile', function () { call('savePresetFile'); });
  on('btnLoadPresetFile', function () { call('loadPresetFile'); });
  on('btnResetPreset', function () {
    if (window.confirm('Reset the project preset to defaults?')) { call('resetProjectPreset'); }
  });
  on('btnNumbering', function () { call('applyNumbering'); });
  on('btnExportReport', function () { call('exportProjectReport'); });

  /* ---------------- PRODUCTION ---------------- */
  window.renderRules = function (p) {
    var el = $('rulePreview');
    if (el) { el.textContent = JSON.stringify(p || {}, null, 2); }
  };

  window.renderProductionChecks = function (rows) {
    fillTable('productionRows', rows, issueRow, 'Production QA passed with no plugin-rule issues.', 5);
    issueSummary('productionSummary', rows);
  };

  function renderProductionStatus() {
    var el = $('productionStatus');
    if (!el) { return; }
    var s = projectStatus || {};
    var fmt = function (t) { return t ? new Date(Number(t) * 1000).toLocaleString() : 'Not recorded'; };
    el.innerHTML = 'Plugin <b>' + esc(s.plugin_version || '1.1.0') + '</b> &bull; revision <b>' + esc(s.revision || 'A') + '</b><br>' +
      'Sources ' + num(s.source_count) + ' &bull; generated ' + num(s.generated_count) + ' &bull; QA issues ' + num(s.qa_issues) + '<br>' +
      'Baseline ' + esc(fmt(s.baseline_at)) + ' &bull; finalized ' + esc(fmt(s.finalized_at));
  }
  window.renderProductionStatus = renderProductionStatus;

  window.renderFinalizeResult = function (p) {
    var el = $('finalizeResult');
    if (!el) { return; }
    var n = (p || {}).numbering || {};
    el.innerHTML = '<b>Finalize completed.</b> Revision ' + esc(n.revision || '') + ' &bull; ' +
      num(n.assigned) + ' new mark(s) &bull; ' + num(n.preserved) + ' preserved &bull; ' +
      ((p || {}).issues || []).length + ' QA issue(s).';
  };

  on('btnFinalize', function () {
    if (window.confirm('Finalize applies marks and saves a new source baseline. Continue?')) { call('finalizeProject'); }
  });
  on('btnProductionCheck', function () { call('productionCheck'); });
  on('btnRefreshRules', function () { call('getRules'); });

  /* ---------------- boot ---------------- */
  refreshProfileSelects();
  // One request; Ruby pushes every panel's data back in a single refresh.
  window.setTimeout(function () { call('ready'); }, 60);
})();
