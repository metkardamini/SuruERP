// Stand-in for supabase-js used ONLY by local Playwright tests (the test machine cannot reach Supabase).
// It mirrors the database rules built in migrations 005 and 009: PIN logins, my_session, login_directory,
// set_staff_pin (self needs current PIN; others need Admin), create_staff, staff/role_permissions tables,
// optimistic locking (version) and Admin-only writes. Real-database behaviour is checked separately in SQL.
(function () {
  var DB_KEY = '__mock_sb_db';
  function load() {
    var raw = localStorage.getItem(DB_KEY);
    if (raw) return JSON.parse(raw);
    var areas = ['poinbox','proddash','prodqueue','qc','rminv','fgtools','procurement','inward','productdata','adminhub','history','failinsights'];
    var perms = {
      ppc: ['poinbox','proddash','prodqueue','qc','rminv','fgtools','procurement','productdata','history','failinsights'],
      prodmgr: ['poinbox','proddash','prodqueue','qc','fgtools','productdata','history','failinsights'],
      staff: ['proddash','prodqueue'],
      store: ['rminv','fgtools','procurement','inward'],
      purchase: ['rminv','fgtools','procurement','inward'],
      qi: ['qc','failinsights'],
      dispatch: ['proddash','history']
    };
    var rp = [];
    ['admin'].concat(Object.keys(perms)).forEach(function (r) {
      areas.forEach(function (a) { rp.push({ role: r, area: a, allowed: r === 'admin' || perms[r].indexOf(a) >= 0, version: 1 }); });
    });
    var db = {
      staff: [
        { id: 'ST-001', name: 'Demo Staff 1', role: 'admin', stages: [], active: true, version: 1, pin: '1111' },
        { id: 'ST-002', name: 'Demo Staff 2', role: 'prodmgr', stages: [], active: true, version: 1, pin: '2222' },
        { id: 'ST-003', name: 'Demo Staff 3', role: 'staff', stages: ['Cutting', 'CNC machining'], active: true, version: 1, pin: '3333' },
        { id: 'ST-004', name: 'Demo Staff 4', role: 'qi', stages: [], active: true, version: 1, pin: '4444' }
      ],
      role_permissions: rp,
      customers: [
        { id: 'CUS-001', name: 'Demo Customer 1', contact: 'Demo Contact 1', terms: 'Net 30 days', active: true, credit_limit: null, address_history: [], extra: {}, version: 1 },
        { id: 'CUS-002', name: 'Demo Customer 2', contact: 'Demo Contact 2', terms: 'Net 45 days', active: true, credit_limit: null, address_history: [], extra: {}, version: 1 }
      ],
      suppliers: [
        { id: 'SUP-001', code: 'SUP-DEMO-001', name: 'Demo Supplier 1', contact: 'Demo Contact 1', city: 'Nashik', materials: 'EN8, SS316', terms: 'Net 30 days', lead_days: 7, active: true, extra: {}, version: 1 },
        { id: 'SUP-002', code: 'SUP-DEMO-002', name: 'Demo Supplier 2', contact: 'Demo Contact 2', city: 'Pune', materials: 'SS316L, Duplex', terms: 'Net 45 days', lead_days: 10, active: true, extra: {}, version: 1 }
      ],
      supplier_bank_details: [],
      stages_master: ['Raw material inward|rm','Cutting|machining','CNC machining|machining','VMC machining|machining','Laser cutting|machining','Grinding|machining','Bending|machining','Heat treatment|outsource','Plating / Coating|outsource','Threading|machining','Welding|machining','Assembly|machining'].map(function (x, i) {
        var p = x.split('|'); return { id: 'STG-' + String(i + 1).padStart(3, '0'), name: p[0], category: p[1], can_qc_after: true, sort_order: i + 1, extra: {}, version: 1 };
      }),
      company_settings: [{ id: 1, name: 'Suru Industries', short_name: 'S', tagline: 'Precision Manufacturing', address: 'Malegaon MIDC, Sinnar', brand_color: '#F5C518', extra: {}, version: 1 }],
      counters: { CUS: 2, SUP: 2, STG: 12 },
      nextSt: 5,
      calls: []
    };
    localStorage.setItem(DB_KEY, JSON.stringify(db));
    return db;
  }
  function saveDb(db) { localStorage.setItem(DB_KEY, JSON.stringify(db)); }
  var SESSION_KEY = 'suru_erp_auth';
  function me(db) {
    var s = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null');
    return s ? db.staff.find(function (x) { return x.id === s.staff_id; }) : null;
  }
  function can(db, area) {
    var u = me(db); if (!u || !u.active) return false;
    if (u.role === 'admin') return true;
    return db.role_permissions.some(function (r) { return r.role === u.role && r.area === area && r.allowed; });
  }
  function err(msg, code) { return { data: null, error: { message: msg, code: code || 'P0001' } }; }
  function ok(d) { return Promise.resolve({ data: d, error: null }); }
  var pub = function (row) { var c = Object.assign({}, row); delete c.pin; return c; };

  // Who may change each table (mirrors migration 005).
  var WRITE = {
    staff: function (db) { return can(db, 'adminhub'); },
    role_permissions: function (db) { return can(db, 'adminhub'); },
    company_settings: function (db) { return can(db, 'adminhub'); },
    customers: function (db) { return can(db, 'poinbox') || can(db, 'adminhub'); },
    suppliers: function (db) { var u = me(db); return u && (u.role === 'admin' || u.role === 'purchase'); },
    supplier_bank_details: function (db) { var u = me(db); return u && (u.role === 'admin' || u.role === 'purchase'); },
    stages_master: function (db) { return can(db, 'productdata'); }
  };
  var READ = { supplier_bank_details: WRITE.supplier_bank_details };
  var KEY = { supplier_bank_details: 'supplier_id', role_permissions: null };
  function query(table) {
    var q = { table: table, filters: [], op: 'select', payload: null };
    var api = {
      select: function () { return api; },
      order: function (c) { q.order = c; return api; },
      eq: function (c, v) { q.filters.push([c, v]); return api; },
      insert: function (p) { q.op = 'insert'; q.payload = p; return api; },
      update: function (p) { q.op = 'update'; q.payload = p; return api; },
      delete: function () { q.op = 'delete'; return api; },
      upsert: function (rows) { q.op = 'upsert'; q.payload = rows; return api; },
      then: function (res, rej) { return run(q).then(res, rej); }
    };
    return api;
  }
  function run(q) {
    var db = load(); var u = me(db);
    db.calls.push({ table: q.table, op: q.op }); saveDb(db);
    if (!u || !u.active) return ok([]);
    var t = db[q.table];
    var match = function (r) { return q.filters.every(function (f) { return r[f[0]] === f[1]; }); };
    var w = WRITE[q.table] ? WRITE[q.table](db) : false;
    if (q.op === 'select') {
      if (READ[q.table] && !READ[q.table](db)) return ok([]);
      var rows = t.filter(match).map(pub);
      if (q.order) rows.sort(function (a, b) { return a[q.order] > b[q.order] ? 1 : -1; });
      return ok(rows);
    }
    if (q.op === 'insert') {
      if (!w) return Promise.resolve(err('new row violates row-level security policy', '42501'));
      var key = KEY[q.table] || 'id';
      if (t.some(function (r) { return r[key] === q.payload[key]; })) return Promise.resolve(err('duplicate key value', '23505'));
      if (q.table === 'supplier_bank_details' && !db.suppliers.some(function (x) { return x.id === q.payload.supplier_id; }))
        return Promise.resolve(err('violates foreign key constraint', '23503'));
      var nr = Object.assign({ version: 1 }, q.payload); nr.version = 1; t.push(nr); saveDb(db); return ok([pub(nr)]);
    }
    if (q.op === 'update') {
      if (!w) return ok([]);
      var hits = t.filter(match);
      for (var i = 0; i < hits.length; i++) {
        if ('version' in q.payload && q.payload.version !== hits[i].version)
          return Promise.resolve(err('stale_row: this ' + q.table + ' record was changed by someone else - reload and try again', '40001'));
      }
      hits.forEach(function (r) { var v = r.version; Object.assign(r, q.payload); r.version = v + 1; });
      saveDb(db); return ok(hits.map(pub));
    }
    if (q.op === 'delete') {
      if (!w) return ok([]);
      var gone = t.filter(match); db[q.table] = t.filter(function (r) { return !match(r); }); saveDb(db); return ok(gone.map(pub));
    }
    if (q.op === 'upsert') {
      if (!w) return Promise.resolve(err('new row violates row-level security policy', '42501'));
      q.payload.forEach(function (p) {
        var r = db.role_permissions.find(function (x) { return x.role === p.role && x.area === p.area; });
        if (r) { r.allowed = p.allowed; r.version += 1; } else db.role_permissions.push(Object.assign({ version: 1 }, p));
      });
      saveDb(db); return ok(null);
    }
    return ok(null);
  }
  function rpc(name, args) {
    var db = load(); var u = me(db);
    db.calls.push({ rpc: name }); saveDb(db);
    if (name === 'login_directory') return ok(db.staff.filter(function (s) { return s.active; }).map(function (s) { return { id: s.id, name: s.name, role: s.role }; }));
    if (name === 'login_branding') return ok([{ name: 'Suru Industries', short_name: 'S', tagline: 'Precision Manufacturing', brand_color: '#F5C518' }]);
    if (!u) return Promise.resolve(err('not_authenticated'));
    if (name === 'my_session') return ok({ id: u.id, name: u.name, role: u.role, stages: u.stages, active: u.active });
    if (name === 'set_staff_pin') {
      if (!/^\d{4}$/.test(args.p_new_pin)) return Promise.resolve(err('PIN must be exactly 4 digits'));
      if (args.p_staff_id === u.id) { if (args.p_current_pin !== u.pin) return Promise.resolve(err('Current PIN is incorrect')); }
      else if (!can(db, 'adminhub')) return Promise.resolve(err("Only Admin can set another person's PIN"));
      db.staff.find(function (s) { return s.id === args.p_staff_id; }).pin = args.p_new_pin; saveDb(db); return ok(null);
    }
    if (name === 'next_id') {
      db.counters[args.p_prefix] = (db.counters[args.p_prefix] || 0) + 1; saveDb(db);
      var pad = { CUS: 3, SUP: 3, STG: 3 }[args.p_prefix] || 4;
      return ok(args.p_prefix + '-' + String(db.counters[args.p_prefix]).padStart(pad, '0'));
    }
    if (name === 'create_staff') {
      if (!can(db, 'adminhub')) return Promise.resolve(err('Only Admin can add staff'));
      var id = 'ST-' + String(db.nextSt++).padStart(3, '0');
      db.staff.push({ id: id, name: args.p_name, role: args.p_role, stages: args.p_stages || [], active: true, version: 1, pin: args.p_pin });
      saveDb(db); return ok(id);
    }
    return Promise.resolve(err('unknown rpc ' + name));
  }
  var auth = {
    signInWithPassword: function (c) {
      var db = load();
      var id = c.email.split('@')[0].toUpperCase();
      var s = db.staff.find(function (x) { return x.id === id; });
      if (!s || 'Suru#' + s.pin !== c.password) return Promise.resolve({ data: {}, error: { message: 'Invalid login credentials' } });
      localStorage.setItem(SESSION_KEY, JSON.stringify({ staff_id: id }));
      return ok({ session: { user: { id: id } } });
    },
    getSession: function () { var s = localStorage.getItem(SESSION_KEY); return ok({ session: s ? JSON.parse(s) : null }); },
    signOut: function () { localStorage.removeItem(SESSION_KEY); return ok(null); }
  };
  window.supabase = { createClient: function () { return { auth: auth, rpc: rpc, from: query }; } };
})();
