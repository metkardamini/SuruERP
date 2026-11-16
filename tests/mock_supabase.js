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

  function query(table) {
    var q = { table: table, filters: [], op: 'select', payload: null, opts: null };
    var api = {
      select: function () { if (q.op === 'none') q.op = 'select'; q.wantRows = true; return api; },
      order: function () { return api; },
      eq: function (c, v) { q.filters.push([c, v]); return api; },
      update: function (p) { q.op = 'update'; q.payload = p; return api; },
      upsert: function (rows, o) { q.op = 'upsert'; q.payload = rows; q.opts = o; return api; },
      then: function (res, rej) { return run(q).then(res, rej); }
    };
    return api;
  }
  function run(q) {
    var db = load(); var u = me(db);
    db.calls.push({ table: q.table, op: q.op }); saveDb(db);
    if (!u || !u.active) return ok([]);
    var rows = db[q.table].filter(function (r) { return q.filters.every(function (f) { return r[f[0]] === f[1]; }); });
    if (q.op === 'select') return ok(rows.map(pub));
    if (q.op === 'update') {
      if (q.table === 'staff' && !can(db, 'adminhub')) return ok([]);
      for (var i = 0; i < rows.length; i++) {
        if ('version' in q.payload && q.payload.version !== rows[i].version)
          return Promise.resolve(err('stale_row: this staff record was changed by someone else - reload and try again', '40001'));
      }
      rows.forEach(function (r) { Object.assign(r, q.payload); r.version += 1; });
      saveDb(db); return ok(rows.map(pub));
    }
    if (q.op === 'upsert') {
      if (!can(db, 'adminhub')) return Promise.resolve(err('new row violates row-level security policy', '42501'));
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
