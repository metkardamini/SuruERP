"""Login & access regression for build v36 (headless Chromium, Supabase replaced by tests/mock_supabase.js).
Usage: python3 tests/test_login_v36.py web/index.html
Console errors from blocked CDNs (fonts/icons/xlsx) are environment noise on this test machine and listed separately."""
import json, os, re, subprocess, sys, time
from playwright.sync_api import sync_playwright

html = os.path.abspath(sys.argv[1]); root, name = os.path.dirname(html), os.path.basename(html)
mock = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mock_supabase.js'), encoding='utf-8').read()
src = open(html, encoding='utf-8').read()
PAGES = sorted(set(re.findall(r"onclick=\"showPage\('([a-z0-9_-]+)'\)\"", src)))

results = []
def check(name, cond, detail=''):
    results.append((name, bool(cond), detail)); print(('PASS ' if cond else 'FAIL ') + name + (' — ' + str(detail) if detail else ''))

srv = subprocess.Popen(['python3', '-m', 'http.server', '8091'], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
app_errors, env_errors = [], []
try:
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context()
        def route(r):
            u = r.request.url
            if 'supabase-js' in u: return r.fulfill(status=200, content_type='application/javascript', body=mock)
            if 'localhost' in u: return r.continue_()
            return r.abort()
        ctx.route('**/*', route)
        pg = ctx.new_page()
        def on_console(m):
            if m.type != 'error': return
            (env_errors if 'Failed to load resource' in m.text else app_errors).append(m.text)
        pg.on('console', on_console)
        pg.on('pageerror', lambda e: app_errors.append('PAGEERR ' + str(e)))
        url = f'http://localhost:8091/{name}'
        pg.goto(url); pg.wait_for_timeout(1500)

        # T1 login directory from the server
        adm = pg.eval_on_selector_all('#ls-user option', 'o=>o.map(x=>x.textContent)')
        prod = pg.eval_on_selector_all('#ls-prod-user option', 'o=>o.map(x=>x.textContent)')
        check('T1 login lists come from the server', len(adm) == 4 and len(prod) == 2 and 'Demo Staff 3' in prod[1], f'admin={adm[1:]}, prod={prod[1:]}')
        check('T1b no PINs anywhere in the page data', '"pin"' not in json.dumps(pg.evaluate('staffList')) and pg.evaluate('staffList.length') == 0)

        def login(staff_id, pin, tab='admin'):
            pg.evaluate(f"lsSetTab('{tab}')")
            sel, pin_el = ('#ls-user', '#ls-pin') if tab == 'admin' else ('#ls-prod-user', '#ls-prod-pin')
            pg.select_option(sel, staff_id); pg.fill(pin_el, pin)
            pg.evaluate('doLogin()'); pg.wait_for_timeout(700)

        # T2 wrong PIN
        login('ST-001', '9999')
        check('T2 wrong PIN refused', pg.is_visible('#login-screen') and 'Incorrect PIN' in pg.inner_text('#ls-err'))

        # T3 admin login
        login('ST-001', '1111')
        cu = pg.evaluate('currentUser')
        check('T3 Admin signs in', pg.is_visible('#app') and cu and cu['id'] == 'ST-001' and cu['role'] == 'admin', cu)
        check('T3b staff list loaded from server', pg.evaluate('staffList.length') == 4)

        # T4 every page renders for Admin with no app errors (smoke regression)
        before = len(app_errors); broken = []
        for pid in PAGES:
            try:
                pg.evaluate(f"showPage('{pid}')"); pg.wait_for_timeout(120)
            except Exception as e:
                broken.append(f'{pid}: {e}')
        check(f'T4 all {len(PAGES)} pages open as Admin without errors', not broken and len(app_errors) == before, broken or app_errors[before:])

        # T5 refresh keeps the session
        pg.reload(); pg.wait_for_timeout(1500)
        check('T5 refresh returns to the app (session kept)', pg.is_visible('#app') and pg.evaluate('currentUser&&currentUser.id') == 'ST-001')

        # T6 role permissions saved to the server
        pg.evaluate("showPage('adminhub')")
        pg.evaluate("toggleRolePerm('qi','prodqueue',true); saveRolePermissions()"); pg.wait_for_timeout(500)
        dbv = pg.evaluate("JSON.parse(localStorage.getItem('__mock_sb_db')).role_permissions.find(r=>r.role==='qi'&&r.area==='prodqueue').allowed")
        check('T6 permission change saved to the server', dbv is True)
        pg.evaluate("toggleRolePerm('qi','prodqueue',false); saveRolePermissions()"); pg.wait_for_timeout(500)

        # T7 admin adds staff with a login
        pg.evaluate("openStaff()"); pg.fill('#sf-n', 'Demo Staff 5'); pg.select_option('#sf-r', 'store'); pg.fill('#sf-p', '5050')
        pg.evaluate('subStaff()'); pg.wait_for_timeout(500)
        check('T7 Admin adds staff (ID from server)', any(s['id'] == 'ST-005' and s['role'] == 'store' for s in pg.evaluate('staffList')))

        # T8 deactivate, then stale-version protection
        pg.evaluate("togStaff('ST-005')"); pg.wait_for_timeout(500)
        act = pg.evaluate("staffList.find(s=>s.id==='ST-005').active")
        check('T8 Admin deactivates staff', act is False)
        pg.evaluate("""(()=>{var d=JSON.parse(localStorage.getItem('__mock_sb_db'));d.staff.find(s=>s.id==='ST-005').version+=5;localStorage.setItem('__mock_sb_db',JSON.stringify(d));})()""")
        pg.evaluate("togStaff('ST-005')"); pg.wait_for_timeout(500)
        toast_txt = pg.evaluate("Array.from(document.querySelectorAll('.toast,#toast,[class*=toast]')).map(e=>e.textContent).join(' | ')")
        check('T8b stale edit refused with a reload message', 'Someone else just changed' in toast_txt, toast_txt[-160:])
        check('T8c own login cannot be deactivated', (pg.evaluate("togStaff('ST-001')") or True) and pg.evaluate("staffList.find(s=>s.id==='ST-001').active") is True)

        # T9 logout clears the session
        pg.evaluate('doLogout()'); pg.wait_for_timeout(600)
        check('T9 logout returns to login and ends the session', pg.is_visible('#login-screen') and pg.evaluate("localStorage.getItem('suru_erp_auth')") is None)
        dirn = pg.eval_on_selector_all('#ls-user option', 'o=>o.map(x=>x.textContent)')
        check('T9b deactivated staff no longer offered at login', not any('Demo Staff 5' in x for x in dirn))

        # T10 nav per role matches the permission matrix
        perms = pg.evaluate("JSON.parse(localStorage.getItem('__mock_sb_db')).role_permissions")
        for sid, pin, role, tab in [('ST-002', '2222', 'prodmgr', 'admin'), ('ST-003', '3333', 'staff', 'prod'), ('ST-004', '4444', 'qi', 'admin')]:
            login(sid, pin, tab)
            shown = set(pg.evaluate("""Array.from(document.querySelectorAll('.nav[data-area]')).filter(e=>e.style.display!=='none'&&getComputedStyle(e).display!=='none').map(e=>e.dataset.area)"""))
            allowed = {r['area'] for r in perms if r['role'] == role and r['allowed']}
            check(f'T10 {role}: menus match permissions', shown <= allowed and shown, f'shown={sorted(shown)} allowed={sorted(allowed)}')
            if role == 'qi':
                # T11 own PIN change
                pg.evaluate("openSetPin()"); pg.fill('#sp-current', '0000'); pg.fill('#sp-new', '4545'); pg.fill('#sp-confirm', '4545')
                pg.evaluate('subSetPin()'); pg.wait_for_timeout(400)
                check('T11 wrong current PIN refused', 'Current PIN is incorrect' in pg.inner_text('#set-pin-err'))
                pg.fill('#sp-current', '4444'); pg.evaluate('subSetPin()'); pg.wait_for_timeout(400)
                newpin = pg.evaluate("JSON.parse(localStorage.getItem('__mock_sb_db')).staff.find(s=>s.id==='ST-004').pin")
                check('T11b PIN changed with correct current PIN', newpin == '4545')
            pg.evaluate('doLogout()'); pg.wait_for_timeout(500)
        login('ST-004', '4545')
        check('T11c new PIN works at next login', pg.is_visible('#app'))
        pg.evaluate('doLogout()'); pg.wait_for_timeout(500)

        # T12 a new build no longer wipes saved data; staff/PINs no longer stored in the browser
        # Plant "yesterday's" data from a different page on the same site, so the open ERP page's own
        # save-on-close cannot overwrite it (that is how it happens in real use: browser closed, new file opened).
        pg.goto(f'http://localhost:8091/__blank_{int(time.time())}'); pg.wait_for_timeout(200)
        pg.evaluate("""(()=>{var d=JSON.parse(localStorage.getItem('suru_erp_v1'));d.buildVersion='v35';d.POS.push({id:'pX',poNo:'KEEP-ME',customer:'X',items:[]});d.staffList=[{id:'ST-001',pin:'1234'}];localStorage.setItem('suru_erp_v1',JSON.stringify(d));})()""")
        pg.goto(url); pg.wait_for_timeout(1500)
        kept = pg.evaluate("POS.some(p=>p.poNo==='KEEP-ME')")
        check('T12 opening a new build keeps saved data (no reset)', kept)
        pg.evaluate('save()')
        stored = pg.evaluate("localStorage.getItem('suru_erp_v1')")
        check('T12b saved browser data has no staff or PINs', '"staffList"' not in stored and '"pin"' not in stored)

        # T13 offline banner
        ctx.set_offline(True); pg.wait_for_timeout(300)
        check('T13 offline banner shows', pg.is_visible('#offline-banner'))
        ctx.set_offline(False); pg.wait_for_timeout(300)
        check('T13b banner hides when back online', not pg.is_visible('#offline-banner'))
        b.close()
finally:
    srv.terminate()

check('ZERO app console errors', not app_errors, app_errors[:5])
print(f'\nEnvironment-only errors (blocked CDNs on test machine): {len(env_errors)}')
failed = [r for r in results if not r[1]]
print(f'RESULT: {len(results) - len(failed)}/{len(results)} passed')
sys.exit(1 if failed else 0)
