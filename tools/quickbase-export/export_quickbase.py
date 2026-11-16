#!/usr/bin/env python3
"""
Quickbase full-app exporter.

Discovers every table in a Quickbase app, then exports the complete schema and
all records. Output feeds the migration to the new EcoProposal CRM database.

Usage:
    export QB_REALM="yourcompany.quickbase.com"
    export QB_USER_TOKEN="b6xxxx_xxxx_x_xxxxxxxxxxxxxxxxxxxxxxxxxx"
    export QB_APP_ID="bxxxxxxxx"
    python3 export_quickbase.py [output_dir]

Output layout (default ./quickbase_export/):
    app.json                     - app metadata
    schema.json                  - every table with its full field definitions
    tables/<name>.json           - all records, values keyed by field label
    tables/<name>.csv            - same records as CSV for spreadsheet review
    files_manifest.json          - every file-attachment reference found
                                   (download URLs, for a later pass)

Only uses the Python standard library — no pip installs needed.
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.quickbase.com/v1"
PAGE_SIZE = 500          # records per query page
PAGE_PAUSE_SECONDS = 0.3 # stay well under Quickbase rate limits


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Missing required environment variable {name}. See usage in the file header.")
    return value


REALM = require_env("QB_REALM")
TOKEN = require_env("QB_USER_TOKEN")
APP_ID = require_env("QB_APP_ID")
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "quickbase_export"


def qb_request(method: str, path: str, body: dict | None = None, query: dict | None = None) -> dict | list:
    url = f"{API}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("QB-Realm-Hostname", REALM)
    request.add_header("Authorization", f"QB-USER-TOKEN {TOKEN}")
    request.add_header("Content-Type", "application/json")
    request.add_header("User-Agent", "EcoProposal-Exporter/1.0")

    for attempt in range(5):
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # 429 = rate limited; honor Retry-After and try again.
            if error.code == 429 and attempt < 4:
                wait = int(error.headers.get("Retry-After", "5"))
                print(f"    rate limited, waiting {wait}s...")
                time.sleep(wait)
                continue
            detail = error.read().decode(errors="replace")
            sys.exit(f"Quickbase API error {error.code} on {method} {path}: {detail}")
    sys.exit(f"Giving up after repeated rate limiting on {method} {path}")


def safe_name(label: str) -> str:
    """Filesystem- and CSV-safe version of a table/field label."""
    return re.sub(r"[^A-Za-z0-9._ -]", "_", label).strip() or "unnamed"


def flatten_value(value):
    """Quickbase wraps every cell as {"value": ...}; values may be scalars,
    user objects, file metadata, or lists. Keep structure as JSON where needed."""
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return json.dumps(value, ensure_ascii=False)


def main() -> None:
    os.makedirs(os.path.join(OUT_DIR, "tables"), exist_ok=True)

    print(f"Exporting Quickbase app {APP_ID} on {REALM}")
    app = qb_request("GET", f"/apps/{APP_ID}")
    with open(os.path.join(OUT_DIR, "app.json"), "w") as f:
        json.dump(app, f, indent=2, ensure_ascii=False)
    print(f"App: {app.get('name', '?')}")

    tables = qb_request("GET", "/tables", query={"appId": APP_ID})
    print(f"Found {len(tables)} tables")

    schema = []
    files_manifest = []

    for table in tables:
        table_id = table["id"]
        table_name = safe_name(table.get("name", table_id))
        print(f"\nTable: {table.get('name')} ({table_id})")

        fields = qb_request("GET", "/fields", query={"tableId": table_id})
        schema.append({"table": table, "fields": fields})
        field_labels = {f["id"]: f.get("label", str(f["id"])) for f in fields}
        file_field_ids = {f["id"] for f in fields if f.get("fieldType") == "file"}
        select = sorted(field_labels)

        # Page through every record.
        records = []
        skip = 0
        while True:
            page = qb_request("POST", "/records/query", body={
                "from": table_id,
                "select": select,
                "options": {"skip": skip, "top": PAGE_SIZE},
            })
            rows = page.get("data", [])
            for row in rows:
                record = {}
                for fid_str, cell in row.items():
                    fid = int(fid_str)
                    label = field_labels.get(fid, fid_str)
                    value = cell.get("value")
                    record[label] = flatten_value(value)
                    if fid in file_field_ids and value:
                        files_manifest.append({
                            "table": table.get("name"),
                            "tableId": table_id,
                            "fieldId": fid,
                            "fieldLabel": label,
                            "record": row.get("3", {}).get("value"),  # fid 3 = Record ID#
                            "file": value,
                        })
                records.append(record)

            total = page.get("metadata", {}).get("totalRecords", 0)
            skip += len(rows)
            print(f"    {skip}/{total} records")
            if not rows or skip >= total:
                break
            time.sleep(PAGE_PAUSE_SECONDS)

        # JSON dump — canonical output for the migration.
        with open(os.path.join(OUT_DIR, "tables", f"{table_name}.json"), "w") as f:
            json.dump(records, f, indent=2, ensure_ascii=False)

        # CSV dump — for eyeballing in Excel/Numbers.
        if records:
            columns = sorted({key for record in records for key in record})
            with open(os.path.join(OUT_DIR, "tables", f"{table_name}.csv"), "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=columns)
                writer.writeheader()
                writer.writerows(records)

    with open(os.path.join(OUT_DIR, "schema.json"), "w") as f:
        json.dump(schema, f, indent=2, ensure_ascii=False)
    with open(os.path.join(OUT_DIR, "files_manifest.json"), "w") as f:
        json.dump(files_manifest, f, indent=2, ensure_ascii=False)

    print(f"\nDone. Export written to {os.path.abspath(OUT_DIR)}")
    print(f"  Tables exported: {len(schema)}")
    print(f"  File attachments referenced: {len(files_manifest)} (download is a separate pass)")


if __name__ == "__main__":
    main()
