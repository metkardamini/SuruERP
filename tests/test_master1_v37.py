"""Master data 1 regression for build v37: company settings, customers, suppliers (+bank), stages.
Headless Chromium; Supabase replaced by tests/mock_supabase.js (same table rules as the real database).
Usage: python3 tests/test_master1_v37.py web/index.html"""
import json, os, re, subprocess, sys, time
from playwright.sync_api import sync_playwright

html = os.path.abspath(sys.argv[1]); root, name = os.path.dirname(html), os.path.basename(html)
mock = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mock_supabase.js'), encoding='utf-8').read()
src = open(html, encoding='utf-8').read()
PAGES = sorted(set(re.findall(r"onclick=\"showPage\('([a-z0-9_-]+)'\)\"", src)))
results = []
def check(n, cond, detail=''):
    results.append((n, bool(cond))); print(('PASS ' if cond else 'FAIL ') + n + (' — ' + str(detail) if detail else ''))

srv = subprocess.Popen(['python3', '-m', 'http.server', '8092'], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
app_errors, env_errors = [], []
try:
    with sync_playwright() as p:
        b = p.chromium.launch(); ctx = b.new_context()
        def route(r):
            u = r.request.url
            if 'supabase-js' in u: return r.fulfill(status=200, content_type='application/javascript', body=mock)
            if 'localhost' in u: return r.continue_()
            return r.abort()
        ctx.route('**/*', route)
        pg = ctx.new_page()
        pg.on('console', lambda m: (env_errors if 'Failed to load resource' in m.text else app_errors).append(m.text) if m.type == 'error' else None)
        pg.on('pageerror', lambda e: app_errors.append('PAGEERR ' + str(e)))
        url = f'http://localhost:8092/{name}'
        pg.goto(url); pg.wait_for_timeout(1200)
        DB = lambda js: pg.evaluate("(()=>{var d=JSON.parse(localStorage.getItem('__mock_sb_db'));" + js + "})()")
        def login(sid, pin, tab='admin'):
            pg.evaluate(f"lsSetTab('{tab}')")
            sel, pe = ('#ls-user', '#ls-pin') if tab == 'admin' else ('#ls-prod-user', '#ls-prod-pin')
            pg.select_option(sel, sid); pg.fill(pe, pin); pg.evaluate('doLogin()'); pg.wait_for_timeout(900)
        def toasts(): return pg.evaluate("Array.from(document.querySelectorAll('[class*=toast]')).map(e=>e.textContent).join(' | ')")
        def settle(ms=900): pg.wait_for_timeout(ms)

        login('ST-001', '1111')
        check('M1 customers loaded from server', [c['name'] for c in pg.evaluate('customers')] == ['Demo Customer 1', 'Demo Customer 2'])
        check('M1b suppliers and stages loaded from server', pg.evaluate('suppliers.length') == 2 and pg.evaluate('stagesMaster.length') == 12)

        # Customers
        pg.evaluate("showPage('customers')"); settle(400)
        pg.evaluate("openCus()"); settle(200)
        for k, v in {'#cus-n': 'Demo Customer 3', '#cus-g': '27AAAAA0000A1ZX', '#cus-ph': '9876543210', '#cus-a': 'MIDC Sinnar', '#cus-cl': '5,00,000'}.items(): pg.fill(k, v)
        pg.evaluate('subCus()'); settle()
        row = DB("return d.customers.find(c=>c.name==='Demo Customer 3')")
        check('M2 new customer saved to server with server ID', row and row['id'] == 'CUS-003', row and row['id'])
        check('M2b credit limit stored as a number', row and row['credit_limit'] == 500000, row and row['credit_limit'])
        check('M2c fields the table has no column for are kept (extra)', row and 'shipAddress' in row['extra'], row and list(row['extra']))
        pg.evaluate("openCus('CUS-003')"); settle(200); pg.fill('#cus-n', 'Demo Customer 3A'); pg.evaluate('subCus()'); settle()
        row = DB("return d.customers.find(c=>c.id==='CUS-003')")
        check('M3 customer edit saved (version 1 -> 2)', row['name'] == 'Demo Customer 3A' and row['version'] == 2, (row['name'], row['version']))
        pg.evaluate("togCus('CUS-003')"); settle()
        check('M4 customer deactivated on server', DB("return d.customers.find(c=>c.id==='CUS-003').active") is False)

        # Two people at once: someone else saves CUS-001 first
        DB("var c=d.customers.find(c=>c.id==='CUS-001');c.name='Changed Elsewhere';c.version+=1;localStorage.setItem('__mock_sb_db',JSON.stringify(d));return 1")
        pg.evaluate("customers.find(c=>c.id==='CUS-001').contact='My Edit';save()"); settle(1200)
        check('M5 stale edit refused, user told', 'Someone else changed this customer' in toasts(), toasts()[-140:])
        check('M5b latest server data shown instead', pg.evaluate("customers.find(c=>c.id==='CUS-001').name") == 'Changed Elsewhere')

        # Suppliers + bank details
        pg.evaluate("showPage('sups')"); settle(400)
        pg.evaluate("openSup()"); settle(200)
        for k, v in {'#sn': 'Demo Supplier 3', '#sc': 'SUP-DEMO-003', '#sph': '9876500000', '#sg': '27BBBBB1111B1ZX', '#sbk': 'Demo Bank', '#sac': '000111222333', '#sif': 'ABCD0123456', '#sld': '5'}.items(): pg.fill(k, v)
        pg.evaluate('subSup()'); settle(1400)
        srow = DB("return d.suppliers.find(s=>s.name==='Demo Supplier 3')")
        bank = DB("return d.supplier_bank_details.find(b=>b.supplier_id==='SUP-003')")
        check('M6 new supplier saved with server ID', srow and srow['id'] == 'SUP-003' and srow['lead_days'] == 5)
        check('M6b bank details kept apart from the supplier row', bank and bank['account_no'] == '000111222333' and 'acc' not in srow['extra'] and 'bank' not in srow['extra'], bank)

        # Stages
        pg.evaluate("showPage('adminhub')"); settle(400)
        pg.evaluate("openAddStage()"); pg.fill('#stg-adm-name', 'Demo Stage X'); pg.evaluate('subStageAdmin()'); settle()
        check('M7 stage added on server', DB("return d.stages_master.some(s=>s.name==='Demo Stage X'&&s.sort_order===13)"))
        pg.evaluate("moveStageAdmin(12,-1)"); settle()
        check('M7b stage order saved', DB("return d.stages_master.find(s=>s.name==='Demo Stage X').sort_order") == 12)
        pg.evaluate("stagesMaster.push({id:'STG-'+Date.now(),name:'Custom From Routing',category:'custom',canQCAfter:true});save()"); settle()
        check('M7c custom stage from a routing screen saved', DB("return d.stages_master.some(s=>s.name==='Custom From Routing'&&s.category==='custom')"))
        pg.evaluate("window.confirm=()=>true;deleteStageAdmin(stagesMaster.findIndex(s=>s.name==='Demo Stage X'))"); settle()
        check('M7d stage deleted on server', DB("return !d.stages_master.some(s=>s.name==='Demo Stage X')"))

        # Company settings
        pg.evaluate("renderAdminHub&&renderAdminHub()"); settle(200)
        pg.evaluate("setVal('co-name','Suru Industries Pvt Ltd');saveCompanySettings()"); settle()
        check('M8 company settings saved on server', DB("return d.company_settings[0].name") == 'Suru Industries Pvt Ltd')

        # Browser storage no longer holds master data
        pg.evaluate('save()'); stored = pg.evaluate("localStorage.getItem('suru_erp_v1')")
        check('M9 customers/suppliers/stages no longer stored in the browser', '"customers"' not in stored and '"suppliers"' not in stored and '"stagesMaster"' not in stored)

        # Every page still opens
        before = len(app_errors); broken = []
        for pid in PAGES:
            try: pg.evaluate(f"showPage('{pid}')"); pg.wait_for_timeout(120)
            except Exception as e: broken.append(f'{pid}: {e}')
        check(f'M10 all {len(PAGES)} pages open as Admin without errors', not broken and len(app_errors) == before, broken or app_errors[before:])

        # Refresh: data comes back from the server
        pg.reload(); settle(1500)
        check('M11 after refresh, data comes from the server', pg.evaluate("customers.some(c=>c.name==='Demo Customer 3A')") and pg.evaluate("suppliers.find(s=>s.id==='SUP-003').acc") == '000111222333')
        pg.evaluate('doLogout()'); settle(500)

        # Production Manager: sees suppliers, but not bank details; cannot change company settings
        login('ST-002', '2222')
        check('M12 Prod. Manager sees suppliers without bank details', pg.evaluate("suppliers.length") == 3 and not pg.evaluate("suppliers.some(s=>s.acc||s.bank||s.ifsc)"))
        pg.evaluate("companySettings.name='Hacked';save()"); settle(1200)
        check('M13 Prod. Manager cannot change company settings (refused, restored)', DB("return d.company_settings[0].name") == 'Suru Industries Pvt Ltd' and pg.evaluate('companySettings.name') == 'Suru Industries Pvt Ltd' and 'do not have permission' in toasts())
        pg.evaluate("suppliers[0].city='Hacked';save()"); settle(1200)
        check('M14 Prod. Manager cannot change suppliers (refused, restored)', DB("return d.suppliers[0].city") != 'Hacked' and pg.evaluate('suppliers[0].city') != 'Hacked')
        pg.evaluate('doLogout()'); settle(500)
        b.close()
finally:
    srv.terminate()
check('ZERO app console errors', not app_errors, app_errors[:5])
print(f'\nEnvironment-only errors (blocked CDNs on test machine): {len(env_errors)}')
failed = [r for r in results if not r[1]]
print(f'RESULT: {len(results) - len(failed)}/{len(results)} passed')
sys.exit(1 if failed else 0)
