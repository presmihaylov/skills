#!/usr/bin/env python3
"""
BigQuery REST API Client

Calls the BigQuery v2 REST API directly using a Google Cloud service account JSON key.
No SDK dependencies — uses only stdlib (urllib, json, base64).

Authentication:
    Set GOOGLE_SERVICE_ACCOUNT_KEY to the raw JSON content of your service account key file.
    The script exchanges it for a short-lived access token via Google's OAuth2 endpoint.

Usage:
    python scripts/bigquery_api.py list-datasets
    python scripts/bigquery_api.py list-tables <dataset_id>
    python scripts/bigquery_api.py get-schema <dataset_id> <table_id>
    python scripts/bigquery_api.py query "SELECT * FROM dataset.table LIMIT 10"
    python scripts/bigquery_api.py query "SELECT * FROM dataset.table" --max-results 50 --dry-run
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BQ_BASE = "https://bigquery.googleapis.com/bigquery/v2"
TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/bigquery"


# ---------------------------------------------------------------------------
# JWT / OAuth helpers (no external deps)
# ---------------------------------------------------------------------------

def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _build_jwt(service_account: dict) -> str:
    header = {"alg": "RS256", "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": service_account["client_email"],
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": now,
        "exp": now + 3600,
    }
    segments = _b64url(json.dumps(header).encode()) + "." + _b64url(json.dumps(payload).encode())
    signature = _rs256_sign(segments.encode(), service_account["private_key"])
    return segments + "." + _b64url(signature)


def _rs256_sign(message: bytes, private_key_pem: str) -> bytes:
    """Sign with RS256 using the subprocess + openssl fallback or cryptography lib."""
    # Try cryptography library first (commonly available)
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)
        return key.sign(message, padding.PKCS1v15(), hashes.SHA256())
    except ImportError:
        pass

    # Fallback: use openssl via subprocess
    import subprocess
    import tempfile

    with tempfile.NamedTemporaryFile(mode="w", suffix=".pem", delete=False) as f:
        f.write(private_key_pem)
        key_path = f.name
    try:
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=message,
            capture_output=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"openssl signing failed: {proc.stderr.decode()}")
        return proc.stdout
    finally:
        os.unlink(key_path)


def _get_access_token(service_account: dict) -> str:
    jwt = _build_jwt(service_account)
    data = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant_type:jwt-bearer",
        "assertion": jwt,
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req) as resp:
        body = json.loads(resp.read())
    return body["access_token"]


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _api_request(method: str, url: str, token: str, body: dict = None) -> dict:
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        try:
            error_json = json.loads(error_body)
            msg = error_json.get("error", {}).get("message", error_body)
        except json.JSONDecodeError:
            msg = error_body
        print(f"Error {e.code}: {msg}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# BigQuery operations
# ---------------------------------------------------------------------------

def list_datasets(token: str, project_id: str):
    url = f"{BQ_BASE}/projects/{project_id}/datasets"
    result = _api_request("GET", url, token)
    datasets = result.get("datasets", [])
    if not datasets:
        print("No datasets found.")
        return
    print(f"Datasets in project '{project_id}':\n")
    for ds in datasets:
        ds_id = ds["datasetReference"]["datasetId"]
        location = ds.get("location", "?")
        print(f"  {ds_id}  (location: {location})")
    print(f"\nTotal: {len(datasets)}")


def list_tables(token: str, project_id: str, dataset_id: str):
    url = f"{BQ_BASE}/projects/{project_id}/datasets/{dataset_id}/tables"
    result = _api_request("GET", url, token)
    tables = result.get("tables", [])
    if not tables:
        print(f"No tables found in '{dataset_id}'.")
        return
    print(f"Tables in '{dataset_id}':\n")
    for t in tables:
        table_id = t["tableReference"]["tableId"]
        ttype = t.get("type", "TABLE")
        rows = t.get("numRows", "?")
        print(f"  {table_id}  (type: {ttype}, rows: {rows})")
    print(f"\nTotal: {len(tables)}")


def get_schema(token: str, project_id: str, dataset_id: str, table_id: str):
    url = f"{BQ_BASE}/projects/{project_id}/datasets/{dataset_id}/tables/{table_id}"
    result = _api_request("GET", url, token)
    fields = result.get("schema", {}).get("fields", [])
    rows = result.get("numRows", "?")
    size = result.get("numBytes", "?")
    print(f"Table: {dataset_id}.{table_id}")
    print(f"Rows: {rows}  Size: {_fmt_bytes(int(size) if size != '?' else 0)}\n")
    print(f"{'Column':<40} {'Type':<15} {'Mode':<12} Description")
    print("-" * 90)
    _print_fields(fields, indent=0)


def _print_fields(fields, indent=0):
    prefix = "  " * indent
    for f in fields:
        name = prefix + f["name"]
        ftype = f.get("type", "?")
        mode = f.get("mode", "NULLABLE")
        desc = f.get("description", "")
        print(f"  {name:<40} {ftype:<15} {mode:<12} {desc}")
        if ftype in ("RECORD", "STRUCT") and "fields" in f:
            _print_fields(f["fields"], indent + 1)


def run_query(token: str, project_id: str, sql: str, max_results: int = 100, dry_run: bool = False):
    url = f"{BQ_BASE}/projects/{project_id}/queries"
    body = {
        "query": sql,
        "useLegacySql": False,
        "maxResults": max_results,
    }
    if dry_run:
        body["dryRun"] = True

    result = _api_request("POST", url, token, body)

    if dry_run:
        bytes_processed = int(result.get("totalBytesProcessed", 0))
        print(f"Dry run — bytes to be processed: {_fmt_bytes(bytes_processed)}")
        return

    schema_fields = result.get("schema", {}).get("fields", [])
    rows = result.get("rows", [])
    total = result.get("totalRows", len(rows))
    job_complete = result.get("jobComplete", False)
    job_id = result.get("jobReference", {}).get("jobId", "")

    # If the job isn't complete yet, poll for results
    if not job_complete and job_id:
        print("Query running, waiting for results...", file=sys.stderr)
        result = _poll_query_results(token, project_id, job_id, max_results)
        schema_fields = result.get("schema", {}).get("fields", [])
        rows = result.get("rows", [])
        total = result.get("totalRows", len(rows))

    col_names = [f["name"] for f in schema_fields]

    if not rows:
        print("Query returned 0 rows.")
        return

    # Format output as a readable table
    row_data = []
    for row in rows:
        values = [_extract_cell(cell) for cell in row.get("f", [])]
        row_data.append(values)

    # Calculate column widths
    widths = [len(c) for c in col_names]
    for rd in row_data:
        for i, val in enumerate(rd):
            if i < len(widths):
                widths[i] = max(widths[i], len(str(val)))

    # Cap column width at 60
    widths = [min(w, 60) for w in widths]

    # Print header
    header = "  ".join(col_names[i].ljust(widths[i]) for i in range(len(col_names)))
    print(header)
    print("  ".join("-" * w for w in widths))

    # Print rows
    for rd in row_data:
        line = "  ".join(str(rd[i] if i < len(rd) else "")[:widths[i]].ljust(widths[i]) for i in range(len(col_names)))
        print(line)

    print(f"\nShowing {len(rows)} of {total} total rows.")


def _poll_query_results(token: str, project_id: str, job_id: str, max_results: int, timeout: int = 120) -> dict:
    url = f"{BQ_BASE}/projects/{project_id}/queries/{job_id}?maxResults={max_results}"
    start = time.time()
    while time.time() - start < timeout:
        result = _api_request("GET", url, token)
        if result.get("jobComplete", False):
            return result
        time.sleep(2)
    print("Error: query timed out waiting for results.", file=sys.stderr)
    sys.exit(1)


def _extract_cell(cell):
    v = cell.get("v")
    if v is None:
        return "NULL"
    return str(v)


def _fmt_bytes(n: int) -> str:
    if n == 0:
        return "0 B"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load_service_account() -> dict:
    raw = os.environ.get("GOOGLE_SERVICE_ACCOUNT_KEY")
    if not raw:
        print("Error: GOOGLE_SERVICE_ACCOUNT_KEY environment variable is not set.", file=sys.stderr)
        print("Set it to the full JSON content of your service account key file.", file=sys.stderr)
        sys.exit(1)
    try:
        sa = json.loads(raw)
    except json.JSONDecodeError:
        print("Error: GOOGLE_SERVICE_ACCOUNT_KEY is not valid JSON.", file=sys.stderr)
        sys.exit(1)
    required = ["client_email", "private_key", "project_id"]
    for field in required:
        if field not in sa:
            print(f"Error: service account JSON is missing '{field}' field.", file=sys.stderr)
            sys.exit(1)
    return sa


def main():
    parser = argparse.ArgumentParser(description="BigQuery REST API client")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("list-datasets", help="List all datasets in the project")

    lt = sub.add_parser("list-tables", help="List tables in a dataset")
    lt.add_argument("dataset_id", help="Dataset ID")

    gs = sub.add_parser("get-schema", help="Get table schema")
    gs.add_argument("dataset_id", help="Dataset ID")
    gs.add_argument("table_id", help="Table ID")

    q = sub.add_parser("query", help="Run a SQL query")
    q.add_argument("sql", help="SQL query string")
    q.add_argument("--max-results", type=int, default=100, help="Max rows to return (default 100)")
    q.add_argument("--dry-run", action="store_true", help="Validate query and estimate bytes processed")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    sa = _load_service_account()
    project_id = sa["project_id"]
    token = _get_access_token(sa)

    if args.command == "list-datasets":
        list_datasets(token, project_id)
    elif args.command == "list-tables":
        list_tables(token, project_id, args.dataset_id)
    elif args.command == "get-schema":
        get_schema(token, project_id, args.dataset_id, args.table_id)
    elif args.command == "query":
        run_query(token, project_id, args.sql, args.max_results, args.dry_run)


if __name__ == "__main__":
    main()
