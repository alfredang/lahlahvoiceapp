#!/usr/bin/env python3
"""Creates App Store provisioning profiles for the iOS targets and installs them."""
import base64, json, os, plistlib, subprocess, urllib.error, urllib.request

HOME = os.path.expanduser("~")

def load_env():
    """Reads private values from the project's gitignored .env file."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")
    values = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"')
    return values


ENV = load_env()
KID, ISS = ENV["ASC_KEY_ID"], ENV["ASC_ISSUER_ID"]
TARGETS = {
    "NovaVoice AppStore": "9QP3Q6Y29U",
    "NovaVoice Keyboard AppStore": "39MA8RWNN2",
    "NovaVoice Widgets AppStore": "C3TDU36DJM",
}
token = subprocess.check_output(
    ["swift", HOME + "/.claude/skills/asc-api-submit/scripts/asc_jwt.swift"], text=True,
    env={**os.environ, "ASC_KEY_ID": KID, "ASC_ISSUER_ID": ISS,
         "ASC_PRIVATE_KEY_PATH": f"{HOME}/.appstoreconnect/private_keys/AuthKey_{KID}.p8"}).strip()


def call(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return res.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        raw = err.read()
        return err.code, json.loads(raw) if raw else {}


_, certs = call("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=50")
cert_ids = [{"type": "certificates", "id": c["id"]} for c in certs["data"]]
print("distribution certificates:", len(cert_ids))
folder = HOME + "/Library/MobileDevice/Provisioning Profiles"
os.makedirs(folder, exist_ok=True)

for name, bundle in TARGETS.items():
    # Profiles are snapshots, so replace any older one that predates the App Group.
    _, existing = call("GET", "/v1/profiles?filter[name]=" + urllib.request.quote(name))
    for old in existing.get("data", []):
        call("DELETE", "/v1/profiles/" + old["id"])
    status, data = call("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
            "certificates": {"data": cert_ids}}}})
    if status >= 300:
        print(name, "FAILED", status, data["errors"][0].get("detail"))
        continue
    content = base64.b64decode(data["data"]["attributes"]["profileContent"])
    start, end = content.find(b"<?xml"), content.find(b"</plist>") + 8
    plist = plistlib.loads(content[start:end])
    with open(f"{folder}/{plist['UUID']}.mobileprovision", "wb") as out:
        out.write(content)
    ents = plist["Entitlements"]
    print(name, "| app id:", ents.get("application-identifier"), "| groups:",
          ents.get("com.apple.security.application-groups"))
