"""Lintas5G step definitions for the unmodified CAMARA QoD r4.3 / QoSProfiles r1.2 feature files."""
import datetime, hashlib, json, re, time, uuid
from behave import given, when, then, step, use_step_matcher
from steps.camara import *
from steps import camara as K
use_step_matcher("re")
S = r"\s+"

def _now(): return datetime.datetime.now(datetime.timezone.utc)
def _dt(s): return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
def _schema_name(ref): return ref.split("/")[-1]
def _resp(ctx):
    try: return ctx.resp.json()
    except Exception: return None
def _lit(v):
    try: return json.loads(v)
    except Exception: return v
def _touch(ctx, p): ctx.req["touched"].add(p.strip())

# ------------------------------------------------------------------ environment / background
@step(r'an environment at "(?P<e>[^"]*)"')
def _(ctx, e): pass
@step(r'the resource "(?P<r>[^"]*)"')
def _(ctx, r): ctx.resource = r
@step(r'the header "(?P<h>[^"]*)" is set to "(?P<v>[^"]*)"')
def _(ctx, h, v): ctx.req["headers"][h] = v
@step(r'the header "Authorization" is set to a valid access token(?: which does not identify a single device)?')
def _(ctx): ctx.req["token"] = ("valid", "a", None)
@step(r'the header "Authorization" is set to a valid access token identifying a device')
def _(ctx): ctx.req["token"] = ("device", "3l", DEV[3])
@step(r'the header "Authorization" is set to a valid 3-legged access token associated to a valid testing device supported by the service')
def _(ctx): ctx.req["token"] = ("device", "3l", DEV[3]); ctx.three_legged = True
@step(r'the header "Authorization" is set to an invalid access token')
def _(ctx): ctx.req["token"] = ("invalid", "a", None)
@step(r'the header "Authorization" is set to an expired access token')
def _(ctx): ctx.req["token"] = ("expired", "a", None)
@step(r'the header "Authorization" is set to an access token that does not include scope "(?P<s>[^"]*)"')
def _(ctx, s): ctx.req["token"] = ("noscope", "a", s)
@step(r'the header "Authorization" is set to a valid access token emitted to a client which did not created the QoS session')
def _(ctx): ctx.req["token"] = ("valid", "b", None)
@step(r'the header "(?P<h>[^"]*)" is not sent')
def _(ctx, h):
    if h == "Authorization": ctx.req["token"] = ("none", "a", None)
    else: ctx.req["headers"][h] = None
@step(r'the header "(?P<h>[^"]*)" complies with the schema at "(?P<s>[^"]*)"')
def _(ctx, h, s): ctx.req["headers"][h] = "__auto__" if h == "x-correlator" else ctx.req["headers"].get(h)
@step(r'the header "(?P<h>[^"]*)" does not comply with the schema at "(?P<s>[^"]*)"')
def _(ctx, h, s): ctx.req["headers"][h] = BAD_XC
@step(r'the request body is set by default to a request body compliant with the schema at "(?P<s>[^"]*)"')
def _(ctx, s): ctx.req["body_set"] = False
@step(r'(?:the request body is set to a valid request body|a request body compliant with the schema at "[^"]*")')
def _(ctx): ctx.req["body"] = K.default_body(ctx.op); ctx.req["body_set"] = True
@step(r'a valid request for "(?P<op>[^"]*)"')
def _(ctx, op): ctx.req["body"] = K.default_body(op); ctx.req["body_set"] = True
@step(r'the request body is not included')
def _(ctx): ctx.req["body"] = None; ctx.req["body_set"] = True
@step(r'the request body is set to \{\}')
def _(ctx): ctx.req["body"] = {}; ctx.req["body_set"] = True
@step(r'the request body is set to any value which is not compliant with the schema at "(?P<s>[^"]*)"')
def _(ctx, s): ctx.req["raw"] = json.dumps(["not", "an", "object"])
@step(r'the path parameter "sessionId" is set by default to a existing QoS session sessionId')
def _(ctx): pass   # resolved lazily at send time (creates a session unless overridden)
@step(r'the path param "name" is set by default to an existing QoS profile name')
def _(ctx): pass

# ------------------------------------------------------------------ devices / tokens semantics
@step(r'a valid testing device supported by the service, identified by the token or provided in the request body')
def _(ctx): K.body(ctx)["device"] = dev(1) if ctx.op != "retrieveSessionsByDevice" else dev(1)
@step(r'a valid testing device supported by the service, identified by the token or provided in the request body, with QoS active sessions associated')
def _(ctx): K.ensure_session(ctx, 1); K.body(ctx)["device"] = dev(1)
@step(r'a valid testing device supported by the service, identified by the token or provided in the request body with no QoS active sessions associated')
def _(ctx): K.body(ctx)["device"] = dev(2)
@step(r'the request body property "\$\.device" is set to a valid device')
def _(ctx): K.body(ctx)["device"] = dev(1)
@step(r'the request body property "(?P<p>[^"]*)" is compliant with the schema but does not identify a valid device')
def _(ctx, p): jset(K.body(ctx), p, {"ipv4Address": {"publicAddress": f"{MOCK_NET}.200", "privateAddress": f"{MOCK_NET}.200"}})
@step(r'that some types of device identifiers are not supported by the implementation')
def _(ctx): pass
@step(r'the request body property "(?P<p>[^"]*)" only includes device identifiers not supported by the implementation')
def _(ctx, p): jset(K.body(ctx), p, {"networkAccessIdentifier": "unsupported-id@example.com"})
@step(r'that the service is not available for all devices commercialized by the operator')
def _(ctx): pass
@step(r'a valid device, identified by the token or provided in the request body, for which the service is not applicable')
def _(ctx): K.body(ctx)["device"] = dev(9)       # fixture: device with service:false -> 422 SERVICE_NOT_APPLICABLE
@step(r'a device for which the service is not applicable, provided in the request body or identified by the access token')
def _(ctx): K.body(ctx)["device"] = dev(10) if ctx.op == "retrieveQosProfiles" else dev(9)   # qos-profiles _06: device without profiles -> 200 []
@step(r'no device is provided in the request body or identified by the access token')
def _(ctx): jdel(K.body(ctx), "$.device"); ctx.req["deleted"].add("$.device")
@step(r'that implementation has QoS Profiles restricted to certain devices')
def _(ctx): pass
@step(r'a device suitable for the restricted QoS Profiles is provided in the request body or identified by the access token')
def _(ctx): K.body(ctx)["device"] = dev(77)

# ------------------------------------------------------------------ body properties
SAMPLES = {"$.applicationServer.ipAddresses": ["198.51.100.10", "198.51.100.11"], "$.devicePorts": {"ports": [40000]},
           "$.applicationServerPorts": {"ports": [18080]}, "$.sinkCredential": None, "$.device": None}
@step(r'the request (?:body )?property\s+"(?P<p>[^"]*)" is set to: \{\}')
def _(ctx, p): jset(K.body(ctx), p, {}); _touch(ctx, p)
@step(r'the request body property "(?P<p>[^"]*)" is set to \{\}')
def _(ctx, p): jset(K.body(ctx), p, {}); _touch(ctx, p)
@step(r'the request (?:body )?property\s+"(?P<p>[^"]*)" is set to "(?P<v>[^"]*)"')
def _(ctx, p, v):
    b = K.body(ctx)
    if p.startswith("$.sinkCredential") and not isinstance(b.get("sinkCredential"), dict): b["sinkCredential"] = {}
    jset(b, p, v); _touch(ctx, p)
@step(r'the request body property\s+"(?P<p>[^"]*)" is set to a value other than "(?P<v>[^"]*)"')
def _(ctx, p, v):
    b = K.body(ctx); b.setdefault("sinkCredential", K.sinkcred()); b.setdefault("sink", ctx.sink_url); jset(b, p, "mac"); _touch(ctx, p)
@step(r'the request property "\$\.qosProfile" is set to a valid QoS Profile as returned by QoS Profiles API')
def _(ctx): K.body(ctx)["qosProfile"] = "QOS_E"
@step(r'the request body property "\$\.(?P<k>qosProfile|name)" is set to an existing QoS profile name')
def _(ctx, k): K.body(ctx)[k] = "QOS_E"
@step(r'the request body property "\$\.(?P<k>qosProfile|name)" is set to a (?:non-existent QoS profile that is compliant with the schema at "[^"]*"|QoS profile name that does not match any existing profile)')
def _(ctx, k): K.body(ctx)[k] = "QOS_NOTEXIST"
@step(r'the requested QoS Profile exists but is not applicable for the session')
def _(ctx): K.body(ctx)["qosProfile"] = "QOS_PARKED"
@step(r'the request body property "\$\.duration" is set to a valid duration for the selected QoS profile')
def _(ctx): K.body(ctx)["duration"] = 60
@step(r'the request body property "(?:\$\.)?duration" is set to an invalid duration for the selected qosProfile')
def _(ctx): K.body(ctx)["duration"] = 99999
@step(r'the request body property "\$\.applicationServer" is set to a valid application server')
def _(ctx): K.body(ctx)["applicationServer"] = {"ipv4Address": "198.51.100.10"}
@step(r'the request body properties "\$\.applicationServer\.ipv4Address" and/or "\$\.applicationServer\.ipv6Address" exist and have valid values which include a subnet mask')
def _(ctx): K.body(ctx)["applicationServer"] = {"ipv4Address": "198.51.100.0/24"}
@step(r'the request body properties "(?P<a>[^"]*)" and/or "(?P<b2>[^"]*)" exist')
def _(ctx, a, b2):
    b = K.body(ctx)
    if not (jexists(b, a) or jexists(b, b2)): jset(b, a, "198.51.100.10")
@step(r'the request body property "(?P<p>[^"]*)" exists')
def _(ctx, p):
    b = K.body(ctx)
    if not jexists(b, p):
        if p == "$.applicationServer.ipAddresses": b.setdefault("applicationServer", {})["ipAddresses"] = list(SAMPLES[p])
        else: jset(b, p, SAMPLES.get(p))
@step(r'the request (?:body )?property "(?P<p>[^"]*)" (?:does not exist|is not included)')
def _(ctx, p): jdel(K.body(ctx), p); ctx.req["deleted"].add(p)
@step(r'the request body properties "(?P<a>[^"]*)" and "(?P<b2>[^"]*)" are not included')
def _(ctx, a, b2):
    for p in (a, b2): jdel(K.body(ctx), p); ctx.req["deleted"].add(p)
def _ips(ctx, n):
    b = K.body(ctx); b["applicationServer"] = {"ipAddresses": [f"198.51.100.{10 + i}" for i in range(n)]}
@step(r'the number of items in request body array "(?P<p>[^"]*)" is greater than 0')
def _(ctx, p):
    if not (jexists(K.body(ctx), p) and len(jget(K.body(ctx), p)) > 0): _ips(ctx, 2)
@step(r'the number of items in request body array "(?P<p>[^"]*)" is less than 17')
def _(ctx, p): assert len(jget(K.body(ctx), p)) < 17
@step(r'the number of items in request body array "(?P<p>[^"]*)" is greater than 1')
def _(ctx, p):
    if len(jget(K.body(ctx), p) if jexists(K.body(ctx), p) else []) <= 1: _ips(ctx, 2)
@step(r'the number of items in request body array "(?P<p>[^"]*)" is greater than 16')
def _(ctx, p): _ips(ctx, 17)
@step(r'the number of items in request body array "(?P<p>[^"]*)" is equal to 0')
def _(ctx, p): K.body(ctx)["applicationServer"] = {"ipAddresses": []}
@step(r'each item within request body array "(?P<p>[^"]*)" is either a valid IPv4 address or valid IPv6 address')
def _(ctx, p):
    import ipaddress
    for a in jget(K.body(ctx), p): ipaddress.ip_address(a)
@step(r'each item within request body array "(?P<p>[^"]*)" is unique with no duplicated values')
def _(ctx, p): v = jget(K.body(ctx), p); assert len(v) == len(set(v))
@step(r'at least two items within request body array "(?P<p>[^"]*)" have the same value')
def _(ctx, p): K.body(ctx)["applicationServer"] = {"ipAddresses": ["198.51.100.10", "198.51.100.10"]}
@step(r'at least one item within request body array "(?P<p>[^"]*)" is not a valid single IPv4 address or single IPv6 address')
def _(ctx, p): K.body(ctx)["applicationServer"] = {"ipAddresses": ["198.51.100.10", "not-an-ip"]}
@step(r'at least one item within request body array "(?P<p>[^"]*)" contains the character \'/\'')
def _(ctx, p): K.body(ctx)["applicationServer"] = {"ipAddresses": ["198.51.100.10", "198.51.100.0/24"]}
BAD = {"$.device.phoneNumber": "not-a-phone", "$.device.ipv4Address": {"publicAddress": "999.1.1.1"},
       "$.device.ipv6Address": "zz::zz::1", "$.device.networkAccessIdentifier": 12345}
@step(r'the request body property "(?P<p>[^"]*)" (?:does not comply with the OAS schema|is not compliant with the schema) at "(?P<s>[^"]*)"')
def _(ctx, p, s):
    b = K.body(ctx)
    if p.startswith("$.device."): b["device"] = {}
    v = BAD.get(p)
    if v is None:
        cur = jget(b, p); v = 12345 if (cur is KeyError or isinstance(cur, str)) else "not-valid"
    jset(b, p, v); _touch(ctx, p)
PARENTS = {"$.devicePorts": {"ports": [40000]}, "$.applicationServerPorts": {"ports": [18080]}, "$.sinkCredential": None}
@step(r'the request body includes the property "(?P<p>[^"]*)" which is not declared in the schema at "(?P<s>[^"]*)"')
def _(ctx, p, s):
    b = K.body(ctx); parent = p.rsplit(".", 1)[0]
    if parent != "$" and not jexists(b, parent):
        if parent == "$.sinkCredential": b["sinkCredential"] = K.sinkcred(); b["sink"] = ctx.sink_url
        else: jset(b, parent, json.loads(json.dumps(PARENTS.get(parent) or {})))
    jset(b, p, "x")
@step(r'the request body property "(?P<p>[^"]*)" is set to a value not between between 0 and 65535')
def _(ctx, p):
    b = K.body(ctx)
    if p.startswith("$.device.ipv4Address"): b["device"] = dev(1)
    for base in ("$.devicePorts", "$.applicationServerPorts"):
        if p.startswith(base + ".ranges"): jset(b, base, {"ranges": [{"from": 1000, "to": 2000}]})
        if p.startswith(base + ".ports"): jset(b, base, {"ports": [1000]})
    jset(b, p.replace("[*]", ""), 70000) if "[*]" not in p else jset(b, p.replace("[*]", ""), [70000])
@step(r'the request property "\$\.sink" is set to a URL where events can be monitored')
def _(ctx): K.body(ctx)["sink"] = ctx.sink_url
@step(r'the request property "\$\.sinkCredential\.accessToken" is set to a valid access token accepted by the events receiver')
def _(ctx):
    b = K.body(ctx); b.setdefault("sinkCredential", {}); b["sinkCredential"]["accessToken"] = K.SINK_TOKEN
    b["sinkCredential"].setdefault("accessTokenExpiresUtc", "2030-01-01T00:00:00Z")
@step(r'a PRIVATE_KEY_JWT configuration has been pre-shared for the notification endpoint')
def _(ctx): ctx.req["token"] = ("valid", "b", None); K.body(ctx)["applicationServer"] = {"ipv4Address": "198.51.100.10"}
@step(r'no PRIVATE_KEY_JWT configuration has been pre-shared for the notification endpoint')
def _(ctx): ctx.req["token"] = ("valid", "a", None); K.body(ctx).setdefault("sink", ctx.sink_url)
@step(r'the request body property "\$\.requestedAdditionalDuration" is set to a valid additional session duration')
def _(ctx): K.body(ctx)["requestedAdditionalDuration"] = 60
@step(r'the request body property "\$\.requestedAdditionalDuration" is set to a value that added to the existing QoS session "(?P<f>[^"]*)" exceeds the "(?P<m>[^"]*)" for the QoS Profile')
def _(ctx, f, m): K.body(ctx)["requestedAdditionalDuration"] = 99999
@step(r'the request body property "(?P<p>[^"]*)" is set to the value (?P<v>.+)')
def _(ctx, p, v): jset(K.body(ctx), p, _lit(v.strip('"<>')))

# ------------------------------------------------------------------ sessions / profiles fixtures
@step(r'an existing QoS session created by operation createSession with qosStatus "(?P<st>[^"]*)"')
def _(ctx, st):
    if st == "UNAVAILABLE": K.ensure_session(ctx, 66, "UNAVAILABLE")
    else: K.ensure_session(ctx, 1, st)
    ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'an existing QoS session created by operation createSession')
def _(ctx): K.ensure_session(ctx, 1); ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'an existing QoS session created by operation createSession with provided values for "(?P<a>[^"]*)" and "(?P<b2>[^"]*)", and with status "(?P<st>[^"]*)"')
def _(ctx, a, b2, st):
    kw = {}
    for p in (a, b2):
        if "devicePorts" in p: kw["devicePorts"] = {"ports": [40000]}
        if "sink" in p and "Credential" not in p: kw["sink"] = ctx.sink_url; kw["sinkCredential"] = K.sinkcred()
    K.ensure_session(ctx, 1, st, **kw); ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'an existing QoS session with qosStatus not "(?P<st>[^"]*)"')
def _(ctx, st): K.ensure_session(ctx, 66, "UNAVAILABLE"); ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'an existing QoS session failed to be created in the last 360 seconds')
def _(ctx): K.ensure_session(ctx, 66, "UNAVAILABLE"); ctx.req["path"]["sessionId"] = ctx.session["sessionId"]; K.body(ctx)["device"] = dev(66)
@step(r'a QoD session already exists for that device')
def _(ctx): K.ensure_session(ctx, 1); K.body(ctx)["device"] = dev(1)
@step(r'a QoS session has been created successfully and includes a valid sink and sinkCredentials')
def _(ctx): K.ensure_session(ctx, 1, sink=ctx.sink_url, sinkCredential=K.sinkcred()); ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'the path parameter "sessionId" is set to the value for that QoS session')
def _(ctx): ctx.req["path"]["sessionId"] = ctx.session["sessionId"]
@step(r'the path parameter "sessionId" is set to a random UUID')
def _(ctx): ctx.req["path"]["sessionId"] = str(uuid.uuid4())
@step(r'the path parameter "sessionId" has not a UUID format')
def _(ctx): ctx.req["path"]["sessionId"] = "not-a-uuid"
@step(r'an existing QoS profile')
def _(ctx): ctx.profile = "QOS_E"
@step(r'the path parameter "name" is set to the value for that QoS profile')
def _(ctx): ctx.req["path"]["name"] = ctx.profile
@step(r'the path parameter "name" is set to a random string compliant with the pattern')
def _(ctx): ctx.req["path"]["name"] = "QOS_RANDOM_" + uuid.uuid4().hex[:6].upper()
@step(r'path parameter "name" has a length not between 3 and 256')
def _(ctx): ctx.req["path"]["name"] = "ab"
@step(r'path parameter "name" does not match the regular expression "(?P<r>.*)"')
def _(ctx, r): ctx.req["path"]["name"] = "bad name!"
@step(r'the threshold of requests has been reached')
def _(ctx): ctx.throttle = True

# ------------------------------------------------------------------ send
@when(r'the request "(?P<op>[^"]*)" is sent')
def _(ctx, op): ctx.op = op; K.send(ctx)
@when(r'the HTTP "(?P<m>[^"]*)" request is sent')
def _(ctx, m): K.send(ctx, m)
@when(r'the QoS status of the session becomes known')
def _(ctx): K.wait_status(ctx, ctx.session["sessionId"], "known")

# ------------------------------------------------------------------ response assertions
@then(r'the response status code is (?P<c>\d+)')
def _(ctx, c): assert ctx.resp.status_code == int(c), f"expected {c} got {ctx.resp.status_code}: {ctx.resp.text[:300]}"
@then(r'the response header "(?P<h>[^"]*)" is "(?P<v>[^"]*)"')
def _(ctx, h, v): assert (ctx.resp.headers.get(h) or "").split(";")[0].strip() == v, f"{h}={ctx.resp.headers.get(h)}"
@then(r'the response header "(?P<h>[^"]*)" has (?:same|the same) value as the request header "(?P<r>[^"]*)"')
def _(ctx, h, r):
    sent = ctx.sent["headers"].get(r)
    if sent is None: return   # header not sent -> nothing to echo
    assert ctx.resp.headers.get(h) == sent, f"{h}: {ctx.resp.headers.get(h)!r} != {sent!r}"
@then(r'the response property "(?P<p>[^"]*)" is (?P<n>\d+)')
def _(ctx, p, n): assert jget(_resp(ctx), p) == int(n), f"{p}={jget(_resp(ctx), p)}"
@then(r'the response property "(?P<p>[^"]*)" is "(?P<v>[^"]*)"')
def _(ctx, p, v):
    got = jget(_resp(ctx), p); allowed = [v]
    # Test_definitions r4.3 allow either documented code for duration errors (spec text); report the exact one
    assert got in allowed, f"{p}={got!r} expected {v!r}"
@then(r'the response property "(?P<p>[^"]*)" is "(?P<a>[^"]*)" or "(?P<b2>[^"]*)"')
def _(ctx, p, a, b2): assert jget(_resp(ctx), p) in (a, b2), f"{p}={jget(_resp(ctx), p)}"
@then(r'the response property "(?P<p>[^"]*)" contains a user[ -]friendly text')
def _(ctx, p): v = jget(_resp(ctx), p); assert isinstance(v, str) and len(v.strip()) > 3, f"{p}={v!r}"
@then(r'the response body complies with the OAS schema at "(?P<s>[^"]*)"')
def _(ctx, s): K.validate(_schema_name(s), _resp(ctx))
@then(r'each item of the response array(?:, if any,)? complies with the OAS schema at "(?P<s>[^"]*)"')
def _(ctx, s):
    r = _resp(ctx); assert isinstance(r, list)
    for x in r: K.validate(_schema_name(s), x)
@then(r'the response array has only one item which complies with the OAS schema at "(?P<s>[^"]*)"')
def _(ctx, s): r = _resp(ctx); assert isinstance(r, list) and len(r) == 1, r; K.validate(_schema_name(s), r[0])
@then(r'each item of the response array, if any, has property "(?P<p>[^"]*)" equal to (?P<v>.+)')
def _(ctx, p, v):
    pp = re.sub(r"^\$\[\*\]", "$", p)
    for x in _resp(ctx): assert jget(x, pp) == v.strip('"<>'), f"{p}={jget(x, pp)}"
@then(r'the response body is \[\]')
def _(ctx): assert _resp(ctx) == [], _resp(ctx)
@then(r'the response property "(?P<p>[^"]*)" does not exist')
def _(ctx, p): assert not jexists(_resp(ctx), p), f"{p} present"
def _items(ctx):
    r = _resp(ctx); return r if isinstance(r, list) else [r]
def _provided(ctx, x, p):
    cb = ctx.create_body or {}; p = p if p.startswith("$") else "$." + p
    if jexists(cb, p): assert jget(x, p) == jget(cb, p), f"{p}: {jget(x, p)} != {jget(cb, p)}"
    else: assert not jexists(x, p), f"{p} present but not provided"
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" exists only if provided for createSession and with the same value')
def _(ctx, p):
    for x in _items(ctx): _provided(ctx, x, p)
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" has the value provided for createSession')
def _(ctx, p):
    for x in _items(ctx): assert jget(x, p) == jget(ctx.create_body, p), f"{p}"
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" has the same value as in the request body')
def _(ctx, p):
    ref = ctx.sent["body"] if ctx.op == "createSession" else ctx.create_body   # get/extend/retrieve: body of the createSession that made it
    pp = p if p.startswith("$") else "$." + p
    for x in _items(ctx): assert jget(x, pp) == jget(ref, pp), f"{p}: {jget(x, pp)} != {jget(ref, pp)}"
@then(r'the response property "(?P<p>[^"]*)" value is equal to the request body property "(?P<q>[^"]*)"')
def _(ctx, p, q): assert jget(_resp(ctx), p) == jget(ctx.sent["body"], q)
@then(r'the response property "(?P<p>[^"]*)" value is equal to path param "(?P<q>[^"]*)"')
def _(ctx, p, q): assert jget(_resp(ctx), p) == ctx.sent["path"].rstrip("/").split("/")[-1]
def _only_if(x, p, cond):
    st = x.get("qosStatus")
    if cond == "avail_past":
        if st == "AVAILABLE": assert p.split(".")[-1] in x and _dt(x[p.split(".")[-1]]) <= _now() + datetime.timedelta(seconds=1)
        else: assert p.split(".")[-1] not in x, f"{p} with {st}"
    elif cond == "notreq_later":
        k = p.split(".")[-1]
        if st != "REQUESTED":
            assert k in x, f"{k} missing with {st}"
            if "startedAt" in x: assert _dt(x[k]) >= _dt(x["startedAt"])
        else: assert k not in x
    elif cond == "unavail":
        assert (p.split(".")[-1] in x) == (st == "UNAVAILABLE"), f"{p} vs {st}"
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" exists only if "(?P<q>[^"]*)" is "(?P<v>[^"]*)" and the value is in the past')
def _(ctx, p, q, v):
    for x in _items(ctx): _only_if(x, p, "avail_past")
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" exists only if "(?P<q>[^"]*)" is not "(?P<v>[^"]*)" and the value is later than "(?P<w>[^"]*)"')
def _(ctx, p, q, v, w):
    for x in _items(ctx): _only_if(x, p, "notreq_later")
@then(r'(?:in all items in the response, )?(?:the response )?property "(?P<p>[^"]*)" exists only if "(?P<q>[^"]*)" is "(?P<v>[^"]*)"')
def _(ctx, p, q, v):
    for x in _items(ctx): _only_if(x, p, "unavail")
COND = {"exists only if provided in the request body and with the same value": "provided",
        "same value as in the request body": "same",
        'exists only if "$.qosStatus" is "AVAILABLE" and value is in the past': "avail_past",
        'exists only if "$.qosStatus" is not "REQUESTED" and later than "$.startedAt"': "notreq_later",
        'exists only if "$.qosStatus" is "UNAVAILABLE"': "unavail"}
@then(r'the response property "(?P<p>[^"]*)" matches the rule: (?P<c>.+)')
def _(ctx, p, c):
    x = _resp(ctx); k = COND[c.strip()]
    if k == "provided":
        if jexists(ctx.sent["body"], p): assert jget(x, p) == jget(ctx.sent["body"], p), p
        else: assert not jexists(x, p), p
    elif k == "same": assert jget(x, p) == jget(ctx.sent["body"], p), p
    else: _only_if(x, p, k)
@then(r'the response property "(?P<p>[^"]*)" is not lower than request property "(?P<q>[^"]*)"')
def _(ctx, p, q): assert jget(_resp(ctx), p) >= jget(ctx.sent["body"], q)
@then(r'the response property "(?P<p>[^"]*)" does not exceed the "(?P<m>[^"]*)" for the QoS Profile')
def _(ctx, p, m):
    prof = _resp(ctx)["qosProfile"]
    r = ctx.http.get(f"{K.P}/qos-profiles/{prof}", headers={"Authorization": "Bearer " + K.token(ctx)}).json()
    mx = r[m]["value"] * {"Seconds": 1, "Minutes": 60, "Hours": 3600, "Days": 86400}.get(r[m]["unit"], 1)
    assert jget(_resp(ctx), p) <= mx, f"{jget(_resp(ctx), p)} > {mx}"
@step(r'the "(?P<m>[^"]*)" for the QoS profile of the session as returned by "(?P<api>[^"]*)" API')
def _(ctx, m, api): pass   # continuation line of the previous step (wrapped text in the feature file)
@then(r'the restricted QoS Profiles are returned in the response')
def _(ctx): assert "QOS_VIP" in [x["name"] for x in _resp(ctx)], _resp(ctx)
@then(r'no restricted QoS Profile is included in the response')
def _(ctx): assert "QOS_VIP" not in [x["name"] for x in _resp(ctx)]

# ------------------------------------------------------------------ events at the sink
def _event(ctx):
    if ctx.event is None:
        sid = ctx.session["sessionId"]
        ev = K.sink_events(ctx, sid); assert ev, "no event at sink for the session"
        ctx.event = ev[-1]; ctx.events = ev
    return ctx.event
@then(r'an event is received at the address of the (?:request property "\$\.sink"|"\$\.sink" provided for createSession)')
def _(ctx):
    if ctx.op == "deleteSession":   # event after delete: UNAVAILABLE / DELETE_REQUESTED
        ev = K.sink_events(ctx, ctx.session["sessionId"], want=lambda e: e["body"]["data"].get("statusInfo") == "DELETE_REQUESTED")
        assert ev, "no DELETE_REQUESTED event"; ctx.event = [e for e in ev if e["body"]["data"].get("statusInfo") == "DELETE_REQUESTED"][-1]
    else: _event(ctx)
@then(r'the event header "Authorization" is set to "Bearer " \+ the value of the (?:request )?property "\$\.sinkCredential\.accessToken"(?: provided for createSession)?')
def _(ctx):
    e = _event(ctx); assert e["auth_scheme"] == "Bearer" and e["auth_sha256"] == hashlib.sha256(K.SINK_TOKEN.encode()).hexdigest()
@then(r'the event header "Content-Type" is set to "(?P<v>[^"]*)"')
def _(ctx, v): assert _event(ctx)["content_type"] == v
@then(r'the event body complies with the OAS schema at "(?P<s>[^"]*)"')
def _(ctx, s): K.validate(_schema_name(s), _event(ctx)["body"])
@then(r'the event body property "\$\.id" is unique')
def _(ctx):
    ids = [json.loads(l)["body"]["id"] for l in open(ctx.sink_log) if "body" in json.loads(l)]; assert len(ids) == len(set(ids))
@then(r'the event body property "(?P<p>[^"]*)" is (?:set to )?"(?P<v>[^"]*)"')
def _(ctx, p, v): assert jget(_event(ctx)["body"], p) == v, jget(_event(ctx)["body"], p)
@then(r'the event body property "(?P<p>[^"]*)" is "(?P<a>[^"]*)" or "(?P<b2>[^"]*)"')
def _(ctx, p, a, b2): assert jget(_event(ctx)["body"], p) in (a, b2)
@then(r'the event body property "(?P<p>[^"]*)" has the same value as createSession response property "(?P<q>[^"]*)"')
def _(ctx, p, q): assert jget(_event(ctx)["body"], p) == jget(ctx.session, q)
@then(r'the event body property "(?P<p>[^"]*)" as returned for createSession')
def _(ctx, p): assert jget(_event(ctx)["body"], "$.data.sessionId") == ctx.session["sessionId"]
@then(r'the event body property "(?P<p>[^"]*)" exists only if "(?P<q>[^"]*)" is "(?P<v>[^"]*)"')
def _(ctx, p, q, v): d = _event(ctx)["body"]; assert jexists(d, p) == (jget(d, q) == v)
