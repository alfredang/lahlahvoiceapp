#!/usr/bin/env python3
"""Fills in the App Store listing from AppStore/metadata.json and uploads screenshots."""
import glob, hashlib, json, os, subprocess, sys, time, urllib.error, urllib.request

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
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
m = json.load(open(os.path.join(ROOT, "AppStore/metadata.json")))
APP = m["app_id"]
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


def report(label, result):
    status, data = result
    detail = "" if status < 300 else " | " + str(data.get("errors", [{}])[0].get("detail"))[:200]
    print(f"{label}: {status}{detail}")
    return status < 300


_, versions = call("GET", f"/v1/apps/{APP}/appStoreVersions?limit=5")
version = versions["data"][0]
vid = version["id"]
print("version", version["attributes"]["versionString"], version["attributes"]["appStoreState"])
report("version", call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
    "type": "appStoreVersions", "id": vid,
    "attributes": {"copyright": m["copyright"], "releaseType": m["release_type"]}}}))

_, locs = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
loc = locs["data"][0]["id"]
report("description", call("PATCH", f"/v1/appStoreVersionLocalizations/{loc}", {"data": {
    "type": "appStoreVersionLocalizations", "id": loc,
    "attributes": {"description": m["description"], "keywords": m["keywords"],
                   "promotionalText": m["promotional_text"], "supportUrl": m["support_url"],
                   "marketingUrl": m["marketing_url"]}}}))

_, infos = call("GET", f"/v1/apps/{APP}/appInfos")
info = infos["data"][0]["id"]
report("category", call("PATCH", f"/v1/appInfos/{info}", {"data": {
    "type": "appInfos", "id": info,
    "relationships": {"primaryCategory": {"data": {"type": "appCategories", "id": m["primary_category"]}}}}}))
_, infolocs = call("GET", f"/v1/appInfos/{info}/appInfoLocalizations")
il = infolocs["data"][0]["id"]
report("subtitle+privacy", call("PATCH", f"/v1/appInfoLocalizations/{il}", {"data": {
    "type": "appInfoLocalizations", "id": il,
    "attributes": {"name": m["name"], "subtitle": m["subtitle"], "privacyPolicyUrl": m["privacy_policy_url"]}}}))

contact = {"contactFirstName": ENV["REVIEW_FIRST_NAME"], "contactLastName": ENV["REVIEW_LAST_NAME"],
           "contactPhone": ENV["REVIEW_PHONE"], "contactEmail": ENV["REVIEW_EMAIL"], "demoAccountRequired": False,
           "notes": m["review_notes"]}
status, detail = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
if status == 200 and detail.get("data"):
    rid = detail["data"]["id"]
    report("review contact", call("PATCH", f"/v1/appStoreReviewDetails/{rid}", {"data": {
        "type": "appStoreReviewDetails", "id": rid, "attributes": contact}}))
else:
    report("review contact", call("POST", "/v1/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": contact,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))


def upload(display_type, pattern):
    _, sets = call("GET", f"/v1/appStoreVersionLocalizations/{loc}/appScreenshotSets")
    target = next((s for s in sets["data"]
                   if s["attributes"]["screenshotDisplayType"] == display_type), None)
    if target:
        _, old = call("GET", f"/v1/appScreenshotSets/{target['id']}/appScreenshots")
        for shot in old.get("data", []):
            call("DELETE", f"/v1/appScreenshots/{shot['id']}")
        set_id = target["id"]
    else:
        _, made = call("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": loc}}}}})
        set_id = made["data"]["id"]
    for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
        raw = open(path, "rb").read()
        status, made = call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(path), "fileSize": len(raw)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if not report("reserve " + os.path.basename(path), (status, made)):
            continue
        shot = made["data"]
        for op in shot["attributes"]["uploadOperations"]:
            req = urllib.request.Request(
                op["url"], method=op["method"], data=raw[op["offset"]:op["offset"] + op["length"]],
                headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            # Screenshot uploads can drop on slow connections, so try each part a few times.
            for attempt in range(4):
                try:
                    urllib.request.urlopen(req, timeout=180).read()
                    break
                except (urllib.error.URLError, TimeoutError, OSError) as err:
                    print("retrying upload:", err)
                    time.sleep(5 * (attempt + 1))
            else:
                raise SystemExit("Upload failed after retries: " + path)
        report(display_type + " " + os.path.basename(path), call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(raw).hexdigest()}}}))


if "--screenshots" in sys.argv:
    upload("APP_IPHONE_67", "AppStore/screenshots/iphone-69/*.png")
