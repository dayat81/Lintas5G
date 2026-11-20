"""Shared state + helpers for the Lintas5G CAMARA step library (behave). No assertions on adapter internals: only HTTP + sink."""
import copy, json, os, re, sys, time, uuid, hashlib
sys.path.insert(0, os.environ.get("QOD_SRC", "/workspace/qod-adapter-013"))
from qod_adapter import spec as SPEC

CLIENTS = {"a": ("conf-a", "conf-a-secret"), "b": ("conf-b", "conf-b-secret"), "3l": ("conf-3l", "conf-3l-secret"),
           "t": ("conf-throttled", "conf-t-secret")}
MOCK_NET = os.environ.get("MOCK_DEVICE_NET", "<MOCK_DEVICE_NET>")  # synthetic mock-backend device /24 prefix (redacted)
DEV = {i: f"{MOCK_NET}.{i}" for i in (1, 2, 3, 9, 10, 66, 77)}
SCOPES = ["quality-on-demand:sessions:create", "quality-on-demand:sessions:read", "quality-on-demand:sessions:update",
          "quality-on-demand:sessions:delete", "quality-on-demand:sessions:retrieve-by-device", "qos-profiles:read"]
SINK_TOKEN = "sink-behave-token-" + uuid.uuid4().hex[:8]
INVALID_TOKEN = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.invalid-signature"
BAD_XC = "bad x-correlator with spaces"
Q, P = "/quality-on-demand/v1", "/qos-profiles/v1"
OPS = {  # operationId -> (method, resource)
    "createSession": ("POST", Q + "/sessions"), "getSession": ("GET", Q + "/sessions/{sessionId}"),
    "deleteSession": ("DELETE", Q + "/sessions/{sessionId}"), "extendQosSessionDuration": ("POST", Q + "/sessions/{sessionId}/extend"),
    "retrieveSessionsByDevice": ("POST", Q + "/retrieve-sessions"), "retrieveQosProfiles": ("POST", P + "/retrieve-qos-profiles"),
    "getQosProfile": ("GET", P + "/qos-profiles/{name}")}

def dev(i): return {"ipv4Address": {"publicAddress": DEV[i], "privateAddress": DEV[i]}}
def default_body(op, i=1):
    if op == "createSession":
        return {"device": dev(i), "applicationServer": {"ipv4Address": "198.51.100.10"}, "applicationServerPorts": {"ports": [18080]},
                "qosProfile": "QOS_E", "duration": 60}
    if op == "extendQosSessionDuration": return {"requestedAdditionalDuration": 60}
    if op == "retrieveSessionsByDevice": return {"device": dev(i)}
    if op == "retrieveQosProfiles": return {}
    return None
def sinkcred():
    return {"credentialType": "ACCESSTOKEN", "accessToken": SINK_TOKEN, "accessTokenType": "bearer", "accessTokenExpiresUtc": "2030-01-01T00:00:00Z"}

def op_of_feature(ctx):
    f = os.path.basename(ctx.feature.filename)
    return re.sub(r"^(quality-on-demand|qos-profiles)-|\.feature$", "", f)

def reset(ctx, scenario):
    ctx.op = op_of_feature(ctx); ctx.tags = set(scenario.effective_tags)
    ctx.req = {"headers": {}, "token": ("valid", "a", None), "body": None, "body_set": False, "path": {}, "raw": None,
               "touched": set(), "deleted": set()}
    ctx.resp = None; ctx.created = []; ctx.session = None; ctx.create_body = None; ctx.throttle = False
    ctx.client = "a"; ctx.event = None; ctx.sink_mark = sink_size(ctx)

def token(ctx, client="a", scopes=None, ttl=None, device=None):
    k = (client, tuple(scopes or ()), ttl, device)
    if k in ctx.tokens and ttl is None: return ctx.tokens[k]
    cid, sec = CLIENTS[client]
    f = {"grant_type": "client_credentials", "client_id": cid, "client_secret": sec, "scope": " ".join(scopes or SCOPES)}
    if ttl is not None: f["ttl"] = str(ttl)
    if device: f["device_ipv4"] = device
    r = ctx.http.post("/oauth2/token", data=f); assert r.status_code == 200, r.text
    ctx.tokens[k] = r.json()["access_token"]; return ctx.tokens[k]

def resolve_token(ctx):
    kind, client, arg = ctx.req["token"]
    if kind == "none": return None
    if kind == "invalid": return INVALID_TOKEN
    if kind == "expired": return token(ctx, client, ttl=-30)
    if kind == "noscope": return token(ctx, client, scopes=[s for s in SCOPES if s != arg])
    if kind == "device": return token(ctx, client, device=arg)
    return token(ctx, client)

# ---- tiny JSONPath ($.a.b, $.a.b[*], $.a.ranges.from where ranges is an array) ----
def _keys(path): return [k for k in path.strip().lstrip("$").lstrip(".").split(".") if k]
def jget(obj, path):
    cur = obj
    m = re.match(r"^\$\[(\d+|\*)\](.*)$", path.strip())
    if m:   # $[0].name / $[*].status on a response array
        if not isinstance(obj, list): return KeyError
        rest = "$" + m.group(2)
        if m.group(1) == "*": return [jget(x, rest) for x in obj]
        i = int(m.group(1)); return jget(obj[i], rest) if i < len(obj) else KeyError
    for k in _keys(path):
        star = k.endswith("[*]"); k = k[:-3] if star else k
        if isinstance(cur, list): cur = [c.get(k) if isinstance(c, dict) else None for c in cur]; continue
        if not isinstance(cur, dict) or k not in cur: return KeyError
        cur = cur[k]
    return cur
def jset(obj, path, val):
    ks = _keys(path); cur = obj
    for i, k in enumerate(ks):
        star = k.endswith("[*]"); k = k[:-3] if star else k
        last = i == len(ks) - 1
        if isinstance(cur, list):
            for c in cur: jset(c, ".".join(ks[i:]), val)
            return
        if last:
            cur[k] = [val] if star else val; return
        if k not in cur or not isinstance(cur[k], (dict, list)): cur[k] = {}
        cur = cur[k]
def jdel(obj, path):
    ks = _keys(path); cur = obj
    for k in ks[:-1]:
        if not isinstance(cur, dict) or k not in cur: return
        cur = cur[k]
    if isinstance(cur, dict): cur.pop(ks[-1], None)
def jexists(obj, path): return jget(obj, path) is not KeyError

def body(ctx):
    if not ctx.req["body_set"]:
        ctx.req["body"] = copy.deepcopy(default_body(ctx.op)); ctx.req["body_set"] = True
    if ctx.req["body"] is None: ctx.req["body"] = {}
    return ctx.req["body"]

def fill_defaults(ctx, b):
    """'Properties not explicitly overwritten can take any values compliant with the schema': complete a sinkCredential."""
    if isinstance(b, dict) and isinstance(b.get("sinkCredential"), dict) and b["sinkCredential"].get("credentialType") == "ACCESSTOKEN":
        for k, v in sinkcred().items():
            if f"$.sinkCredential.{k}" not in ctx.req["touched"] | ctx.req["deleted"]: b["sinkCredential"].setdefault(k, v)
    if isinstance(b, dict) and "sinkCredential" in b and "sink" not in b and "$.sink" not in ctx.req["deleted"]: b["sink"] = ctx.sink_url

def ensure_session(ctx, i=1, status=None, client="a", **kw):
    """Create a QoS session (fixture) with createSession; i=66 is the mock 'network failure' device -> UNAVAILABLE."""
    b = default_body("createSession", i); b.update(kw)
    t = token(ctx, client)
    r = ctx.http.post(Q + "/sessions", json=b, headers={"Authorization": "Bearer " + t, "x-correlator": "fx-" + uuid.uuid4().hex[:8]})
    assert r.status_code == 201, f"fixture create {r.status_code} {r.text[:200]}"
    o = r.json(); ctx.created.append((o["sessionId"], client)); ctx.session = o; ctx.create_body = b
    if status: wait_status(ctx, o["sessionId"], status, client)
    return o

def wait_status(ctx, sid, st, client="a", to=4):
    t0 = time.time()
    while time.time() - t0 < to:
        r = ctx.http.get(f"{Q}/sessions/{sid}", headers={"Authorization": "Bearer " + token(ctx, client)})
        if r.status_code == 200 and (r.json()["qosStatus"] == st or (st == "known" and r.json()["qosStatus"] != "REQUESTED")):
            ctx.session = r.json(); return r.json()
        time.sleep(0.05)
    raise AssertionError(f"status {st} not reached")

def send(ctx, method=None):
    m, res = OPS[ctx.op]
    if method: m = method
    path = res
    for k in re.findall(r"{(\w+)}", res):
        v = ctx.req["path"].get(k)
        if v is None:   # Background default: existing session / existing profile
            v = ensure_session(ctx)["sessionId"] if k == "sessionId" else "QOS_E"
        path = path.replace("{" + k + "}", v)
    h = {}
    t = resolve_token(ctx)
    if t: h["Authorization"] = "Bearer " + t
    xc = ctx.req["headers"].get("x-correlator", "__auto__")
    if xc == "__auto__": xc = "bh-" + uuid.uuid4().hex[:12]
    if xc is not None: h["x-correlator"] = xc
    for k, v in ctx.req["headers"].items():
        if k not in ("x-correlator",) and v is not None: h[k] = v
    kw = {}
    if ctx.req["raw"] is not None: kw["content"] = ctx.req["raw"]; h.setdefault("Content-Type", "application/json")
    elif m in ("POST", "PUT", "PATCH"):
        if ctx.req["body_set"] and ctx.req["body"] is None: pass   # body not included
        else:
            b = body(ctx); fill_defaults(ctx, b); kw["content"] = json.dumps(b); h.setdefault("Content-Type", "application/json")
    ctx.sent = {"method": m, "path": path, "headers": h, "body": json.loads(kw["content"]) if "content" in kw and ctx.req["raw"] is None else None}
    if ctx.throttle:
        tt = token(ctx, "t"); h["Authorization"] = "Bearer " + tt
        for _ in range(15):
            r = ctx.http.request(m, path, headers=h, **kw)
            if r.status_code == 429: break
        time.sleep(0.5)
    else:
        r = ctx.http.request(m, path, headers=h, **kw)
    ctx.resp = r
    if ctx.op == "createSession" and r.status_code == 201:
        ctx.created.append((r.json()["sessionId"], ctx.req["token"][1])); ctx.create_body = ctx.sent["body"]; ctx.session = r.json()
    return r

def cleanup(ctx):
    for sid, c in getattr(ctx, "created", []):
        try:
            cl = c if c in CLIENTS else "a"
            t = token(ctx, cl, device=DEV[3]) if cl == "3l" else token(ctx, cl)
            ctx.http.delete(f"{Q}/sessions/{sid}", headers={"Authorization": "Bearer " + t})
        except Exception: pass

def validate(name, obj, which=None):
    sp = SPEC.qosp if (which == "qosp" or name in ("QosProfile",) or name.startswith("QosProfile")) else SPEC.qod
    try: v = sp.validator(name)
    except Exception:
        v = (SPEC.qod if sp is SPEC.qosp else SPEC.qosp).validator(name)
    errs = list(v.iter_errors(obj)); assert not errs, f"schema {name}: {errs[0].message[:200]}"

def sink_size(ctx):
    try: return sum(1 for _ in open(ctx.sink_log))
    except FileNotFoundError: return 0
def sink_events(ctx, sid, to=5, want=None):
    t0 = time.time()
    while time.time() - t0 < to:
        ev = []
        try:
            for l in open(ctx.sink_log):
                e = json.loads(l)
                if ((e.get("body") or {}).get("data") or {}).get("sessionId") == sid: ev.append(e)
        except FileNotFoundError: pass
        if ev and (want is None or any(want(e) for e in ev)): return ev
        time.sleep(0.1)
    return []
