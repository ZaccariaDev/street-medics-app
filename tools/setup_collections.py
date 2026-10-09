#!/usr/bin/env python3
import json, urllib.request, urllib.error, sys

BASE = "http://127.0.0.1:8090"

def req(method, path, data=None, token=None):
    url = BASE + path
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, method=method)
    r.add_header("Content-Type", "application/json")
    if token:
        r.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, ""

st, res = req("POST", "/api/collections/_superusers/auth-with-password",
              {"identity": "admin@local.dev", "password": "medics-admin-2026"})
if st != 200:
    print("AUTH FAIL", st, res); sys.exit(1)
token = res["token"]
print("auth OK")

collections = [
    {
        "name": "reports", "type": "base",
        "fields": [
            {"name": "senderPhone", "type": "text"},
            {"name": "position", "type": "json", "maxSize": 2000},
            {"name": "description", "type": "text"},
            {"name": "status", "type": "text"},
        ],
        "listRule": "", "viewRule": "", "createRule": "", "updateRule": "", "deleteRule": "",
    },
    {
        "name": "medics", "type": "base",
        "fields": [
            {"name": "name", "type": "text"},
            {"name": "phone", "type": "text"},
            {"name": "position", "type": "json", "maxSize": 2000},
            {"name": "available", "type": "bool"},
        ],
        "listRule": "", "viewRule": "", "createRule": "", "updateRule": "", "deleteRule": "",
    },
]

for c in collections:
    st, res = req("POST", "/api/collections", c, token)
    if st in (200, 201):
        print(f"created {c['name']}: {res.get('id')}")
    else:
        print(f"FAIL {c['name']}: {st} {json.dumps(res)[:400] if isinstance(res, dict) else res}")

# Allow public signup on users
st, res = req("GET", "/api/collections/users", token=token)
if st == 200:
    users = res
    users["createRule"] = ""
    users["listRule"] = ""
    users["viewRule"] = ""
    st2, res2 = req("PATCH", "/api/collections/" + users["id"], users, token)
    print("users rules ->", st2)

st, res = req("GET", "/api/collections", token=token)
if st == 200:
    items = res.get("items") or res.get("data") or []
    print("collections now:", [c["name"] for c in items])
