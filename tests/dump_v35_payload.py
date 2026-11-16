"""Load the ERP in headless Chromium and dump what it saves to localStorage.
Usage: python3 tests/dump_v35_payload.py web/index.html out.json
Used on 16 Nov to derive the Supabase schema from build v35."""
import json, subprocess, sys, time, os
from playwright.sync_api import sync_playwright

html, out = sys.argv[1], sys.argv[2]
root, name = os.path.dirname(os.path.abspath(html)), os.path.basename(html)
srv = subprocess.Popen(['python3', '-m', 'http.server', '8080'], cwd=root,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
errs = []
try:
    with sync_playwright() as p:
        b = p.chromium.launch(); pg = b.new_page()
        pg.on('console', lambda m: errs.append(m.text) if m.type == 'error' else None)
        pg.on('pageerror', lambda e: errs.append('PAGEERR ' + str(e)))
        pg.goto(f'http://localhost:8080/{name}'); pg.wait_for_timeout(3000)
        raw = pg.evaluate("()=>{save();return localStorage.getItem(PERSIST_KEY)}")
        json.dump(json.loads(raw), open(out, 'w'), indent=1)
        b.close()
finally:
    srv.terminate()
print('console errors:', len(errs))
for e in errs: print(' ', e[:160])
