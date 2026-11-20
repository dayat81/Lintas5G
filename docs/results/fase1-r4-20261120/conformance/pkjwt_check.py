#!/usr/bin/env python3
"""pkjwt_check.py: end-to-end PRIVATE_KEY_JWT sinkCredential check (adapter 0.1.3 + reference sink/token endpoint).
Client conf-b (pre-shared) creates a session with sink=/pkjwt and PRIVATE_KEY_JWT; expects: 201 + jwksUri, an assertion verified by
the sink against the adapter's local JWKS, the callback carrying the issued token (auth_valid), and 422 for a non-pre-shared client."""
import httpx, json, os, time, sys
B, LOG = "http://127.0.0.1:18080", "/tmp/qod-conf/sink.jsonl"; c = httpx.Client(base_url=B)
def tok(cid, sec): return c.post("/oauth2/token", data={"grant_type": "client_credentials", "client_id": cid, "client_secret": sec}).json()["access_token"]
MOCK_NET = os.environ.get("MOCK_DEVICE_NET", "<MOCK_DEVICE_NET>")  # synthetic mock-backend device prefix (redacted)
body = {"device": {"ipv4Address": {"publicAddress": MOCK_NET + ".2", "privateAddress": MOCK_NET + ".2"}}, "applicationServer": {"ipv4Address": "198.51.100.10"},
        "qosProfile": "QOS_E", "duration": 30, "sink": "https://127.0.0.1:18443/pkjwt", "sinkCredential": {"credentialType": "PRIVATE_KEY_JWT"}}
out = {}
r = c.post("/quality-on-demand/v1/sessions", json=body, headers={"Authorization": "Bearer " + tok("conf-b", "conf-b-secret")})
out["create_preshared"] = {"http": r.status_code, "sinkCredential": r.json().get("sinkCredential")}
sid = r.json()["sessionId"]; time.sleep(1.5)
rec = [json.loads(l) for l in open(LOG)]
out["token_requests"] = [{k: x[k] for k in ("assertion_valid", "kid") if k in x} for x in rec if x.get("path") == "/token"]
out["events"] = [{"qosStatus": x["body"]["data"]["qosStatus"], "auth_valid": x.get("auth_valid")} for x in rec if x.get("path") == "/pkjwt" and x["body"]["data"]["sessionId"] == sid]
c.delete(f"/quality-on-demand/v1/sessions/{sid}", headers={"Authorization": "Bearer " + tok("conf-b", "conf-b-secret")})
body["device"]["ipv4Address"] = {"publicAddress": MOCK_NET + ".1", "privateAddress": MOCK_NET + ".1"}
r2 = c.post("/quality-on-demand/v1/sessions", json=body, headers={"Authorization": "Bearer " + tok("conf-a", "conf-a-secret")})
out["create_not_preshared"] = {"http": r2.status_code, "code": r2.json().get("code")}
out["jwks_keys"] = [{k: v for k, v in kk.items() if k in ("kid", "alg", "use", "kty")} for kk in c.get("/.well-known/sink-jwks.json").json()["keys"]]
ok = (out["create_preshared"]["http"] == 201 and out["create_preshared"]["sinkCredential"]["credentialType"] == "PRIVATE_KEY_JWT"
      and any(t.get("assertion_valid") for t in out["token_requests"]) and out["events"] and all(e["auth_valid"] for e in out["events"])
      and out["create_not_preshared"] == {"http": 422, "code": "PRIVATE_KEY_JWT_NOT_CONFIGURED"})
out["verdict"] = "PASS" if ok else "FAIL"; print(json.dumps(out, indent=1)); sys.exit(0 if ok else 1)
