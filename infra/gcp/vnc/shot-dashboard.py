#!/usr/bin/env python3
"""Screenshot of the combined page (box side). Credentials only from env WEBPW / VNCPW (never printed).
VNCPW is injected into the iframe URL only inside this headless browser (route rewrite), so the shot shows Android.
usage: WEBPW=.. VNCPW=.. python shot-dashboard.py <url> <out.png>"""
import os, sys, time
from playwright.sync_api import sync_playwright
url, out = sys.argv[1].rstrip('/'), sys.argv[2]
with sync_playwright() as p:
    b = p.chromium.launch(executable_path=os.environ.get("CHROME", "/usr/bin/google-chrome"), args=["--no-sandbox"])
    ctx = b.new_context(viewport={"width": 1440, "height": 860}, http_credentials={"username": "lab", "password": os.environ["WEBPW"]})
    def lab(route):
        r = route.fetch(); body = r.text()
        if os.environ.get("VNCPW"):
            from urllib.parse import quote
            body = body.replace("vnc.html?autoconnect=1", "vnc.html?password=" + quote(os.environ["VNCPW"]) + "&autoconnect=1")
        route.fulfill(response=r, body=body)
    ctx.route("**/", lab)
    pg = ctx.new_page(); pg.goto(url + "/", wait_until="load")
    time.sleep(float(os.environ.get("WAIT", "15")))
    pg.screenshot(path=out)
    f = pg.frame_locator("#vnc")
    print("dash_updated:", pg.inner_text("#upd"), "| attach:", pg.inner_text("#att"), "| stale banner visible:", pg.is_visible("#stale"))
    b.close()
