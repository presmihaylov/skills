#!/usr/bin/env python3
"""
Google Sheets REST API Client

Calls the Google Sheets API v4 and Google Drive API v3 directly using a Google Cloud
service account JSON key. No SDK dependencies — uses only stdlib (urllib, json, base64).

Authentication:
    Set GOOGLE_SERVICE_ACCOUNT_KEY to the base64-encoded JSON content of your service
    account key file. (Raw JSON is also accepted for backwards compatibility.)
    The script exchanges it for a short-lived access token via Google's OAuth2 endpoint.

    Important: the service account email must be shared as an editor on the target
    spreadsheet for read/write access.

Usage:
    python scripts/sheets_api.py search "quarterly report"
    python scripts/sheets_api.py info <spreadsheet_id>
    python scripts/sheets_api.py list-sheets <spreadsheet_id>
    python scripts/sheets_api.py get <spreadsheet_id> Sheet1!A1:D10
    python scripts/sheets_api.py batch-get <spreadsheet_id> Sheet1!A1:B5 Sheet2!C1:D5
    python scripts/sheets_api.py update <spreadsheet_id> Sheet1!A1:B2 '[["Name","Score"],["Alice","95"]]'
    python scripts/sheets_api.py append <spreadsheet_id> Sheet1!A:B '[["Bob","87"],["Carol","92"]]'
    python scripts/sheets_api.py clear <spreadsheet_id> Sheet1!A1:D10
    python scripts/sheets_api.py create "My New Spreadsheet"
    python scripts/sheets_api.py add-sheet <spreadsheet_id> "New Tab"
    python scripts/sheets_api.py delete-sheet <spreadsheet_id> <sheet_id>
    python scripts/sheets_api.py find-replace <spreadsheet_id> "old" "new"
    python scripts/sheets_api.py lookup <spreadsheet_id> "search term"
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SHEETS_BASE = "https://sheets.googleapis.com/v4/spreadsheets"
DRIVE_BASE = "https://www.googleapis.com/drive/v3"
TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive.readonly"


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
    """Sign with RS256 using the cryptography lib or openssl CLI fallback."""
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)
        return key.sign(message, padding.PKCS1v15(), hashes.SHA256())
    except ImportError:
        pass

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
            raw = resp.read()
            if not raw:
                return {}
            return json.loads(raw)
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
# Spreadsheet operations
# ---------------------------------------------------------------------------

def search_spreadsheets(token: str, query: str, max_results: int = 20):
    """Search for spreadsheets by name using Google Drive API."""
    q = f"mimeType='application/vnd.google-apps.spreadsheet' and name contains '{query}' and trashed=false"
    params = urllib.parse.urlencode({
        "q": q,
        "pageSize": max_results,
        "fields": "files(id,name,modifiedTime,owners)",
        "orderBy": "modifiedTime desc",
    })
    url = f"{DRIVE_BASE}/files?{params}"
    result = _api_request("GET", url, token)
    files = result.get("files", [])
    if not files:
        print("No spreadsheets found.")
        return
    print(f"Spreadsheets matching '{query}':\n")
    for f in files:
        owners = ", ".join(o.get("displayName", o.get("emailAddress", "?")) for o in f.get("owners", []))
        print(f"  {f['name']}")
        print(f"    ID: {f['id']}")
        print(f"    Modified: {f.get('modifiedTime', '?')}  Owner: {owners}")
        print()
    print(f"Total: {len(files)}")


def get_spreadsheet_info(token: str, spreadsheet_id: str):
    """Get spreadsheet metadata (title, sheets, locale, timezone)."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}?fields=spreadsheetId,properties,sheets.properties"
    result = _api_request("GET", url, token)
    props = result.get("properties", {})
    print(f"Title: {props.get('title', '?')}")
    print(f"Locale: {props.get('locale', '?')}  Timezone: {props.get('timeZone', '?')}")
    print(f"ID: {result.get('spreadsheetId', '?')}")
    sheets = result.get("sheets", [])
    if sheets:
        print(f"\nSheets ({len(sheets)}):")
        for s in sheets:
            sp = s.get("properties", {})
            grid = sp.get("gridProperties", {})
            rows = grid.get("rowCount", "?")
            cols = grid.get("columnCount", "?")
            hidden = " (hidden)" if sp.get("hidden") else ""
            print(f"  [{sp.get('sheetId', '?')}] {sp.get('title', '?')}  ({rows} rows x {cols} cols){hidden}")


def list_sheets(token: str, spreadsheet_id: str):
    """List all sheet tabs in a spreadsheet."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}?fields=sheets.properties"
    result = _api_request("GET", url, token)
    sheets = result.get("sheets", [])
    if not sheets:
        print("No sheets found.")
        return
    print(f"{'Sheet ID':<12} {'Title':<40} {'Rows':<10} {'Cols':<10} Hidden")
    print("-" * 85)
    for s in sheets:
        sp = s.get("properties", {})
        grid = sp.get("gridProperties", {})
        print(f"{sp.get('sheetId', '?'):<12} {sp.get('title', '?'):<40} {grid.get('rowCount', '?'):<10} {grid.get('columnCount', '?'):<10} {'yes' if sp.get('hidden') else 'no'}")


def get_values(token: str, spreadsheet_id: str, range_: str, render: str = "FORMATTED_VALUE"):
    """Read values from a range (A1 notation)."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    params = urllib.parse.urlencode({
        "valueRenderOption": render,
        "dateTimeRenderOption": "FORMATTED_STRING",
    })
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values/{urllib.parse.quote(range_)}?{params}"
    result = _api_request("GET", url, token)
    _print_values(result.get("values", []), result.get("range", range_))


def batch_get_values(token: str, spreadsheet_id: str, ranges: list, render: str = "FORMATTED_VALUE"):
    """Read values from multiple ranges in one request."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    params = urllib.parse.urlencode({
        "valueRenderOption": render,
        "dateTimeRenderOption": "FORMATTED_STRING",
        "ranges": ranges,
    }, doseq=True)
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values:batchGet?{params}"
    result = _api_request("GET", url, token)
    for vr in result.get("valueRanges", []):
        _print_values(vr.get("values", []), vr.get("range", "?"))
        print()


def update_values(token: str, spreadsheet_id: str, range_: str, values_json: str,
                  input_option: str = "USER_ENTERED"):
    """Write values to a range."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    values = json.loads(values_json)
    params = urllib.parse.urlencode({"valueInputOption": input_option})
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values/{urllib.parse.quote(range_)}?{params}"
    body = {
        "range": range_,
        "majorDimension": "ROWS",
        "values": values,
    }
    result = _api_request("PUT", url, token, body)
    updated = result.get("updatedCells", 0)
    print(f"Updated {updated} cells in {result.get('updatedRange', range_)}")


def append_values(token: str, spreadsheet_id: str, range_: str, values_json: str,
                  input_option: str = "USER_ENTERED"):
    """Append rows after existing data in a range."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    values = json.loads(values_json)
    params = urllib.parse.urlencode({
        "valueInputOption": input_option,
        "insertDataOption": "INSERT_ROWS",
    })
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values/{urllib.parse.quote(range_)}:append?{params}"
    body = {
        "majorDimension": "ROWS",
        "values": values,
    }
    result = _api_request("POST", url, token, body)
    updates = result.get("updates", {})
    updated = updates.get("updatedCells", 0)
    print(f"Appended {updates.get('updatedRows', 0)} rows ({updated} cells) at {updates.get('updatedRange', range_)}")


def clear_values(token: str, spreadsheet_id: str, range_: str):
    """Clear values in a range (preserves formatting)."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values/{urllib.parse.quote(range_)}:clear"
    result = _api_request("POST", url, token, {})
    print(f"Cleared range: {result.get('clearedRange', range_)}")


def create_spreadsheet(token: str, title: str):
    """Create a new spreadsheet."""
    body = {"properties": {"title": title}}
    result = _api_request("POST", SHEETS_BASE, token, body)
    print(f"Created spreadsheet: {result.get('properties', {}).get('title', '?')}")
    print(f"ID: {result.get('spreadsheetId', '?')}")
    print(f"URL: {result.get('spreadsheetUrl', '?')}")


def add_sheet(token: str, spreadsheet_id: str, title: str):
    """Add a new sheet tab to a spreadsheet."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    body = {
        "requests": [{"addSheet": {"properties": {"title": title}}}]
    }
    result = _api_request("POST", url, token, body)
    replies = result.get("replies", [{}])
    new_props = replies[0].get("addSheet", {}).get("properties", {})
    print(f"Added sheet '{new_props.get('title', title)}' (ID: {new_props.get('sheetId', '?')})")


def delete_sheet(token: str, spreadsheet_id: str, sheet_id: int):
    """Delete a sheet tab by its numeric ID."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    body = {
        "requests": [{"deleteSheet": {"sheetId": sheet_id}}]
    }
    _api_request("POST", url, token, body)
    print(f"Deleted sheet ID {sheet_id}")


def find_replace(token: str, spreadsheet_id: str, find: str, replace: str,
                 match_case: bool = False, use_regex: bool = False,
                 sheet_name: str = None, all_sheets: bool = True):
    """Find and replace text across the spreadsheet."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    fr_request = {
        "find": find,
        "replacement": replace,
        "matchCase": match_case,
        "searchByRegex": use_regex,
    }
    if sheet_name:
        # Resolve sheet name to ID
        sid = _resolve_sheet_id(token, spreadsheet_id, sheet_name)
        if sid is not None:
            fr_request["sheetId"] = sid
    else:
        fr_request["allSheets"] = all_sheets

    body = {"requests": [{"findReplace": fr_request}]}
    result = _api_request("POST", url, token, body)
    replies = result.get("replies", [{}])
    fr_result = replies[0].get("findReplace", {})
    found = fr_result.get("occurrencesChanged", 0)
    sheets_changed = fr_result.get("sheetsChanged", 0)
    print(f"Replaced {found} occurrences across {sheets_changed} sheet(s)")


def lookup_row(token: str, spreadsheet_id: str, query: str, range_: str = None):
    """Find the first row containing the query string."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    # If no range given, get all sheet names and search the first one
    if not range_:
        sheets_url = f"{SHEETS_BASE}/{spreadsheet_id}?fields=sheets.properties.title"
        sheets_result = _api_request("GET", sheets_url, token)
        sheets = sheets_result.get("sheets", [])
        if not sheets:
            print("No sheets found.")
            return
        range_ = sheets[0].get("properties", {}).get("title", "Sheet1")

    params = urllib.parse.urlencode({
        "valueRenderOption": "FORMATTED_VALUE",
        "dateTimeRenderOption": "FORMATTED_STRING",
    })
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values/{urllib.parse.quote(range_)}?{params}"
    result = _api_request("GET", url, token)
    values = result.get("values", [])
    query_lower = query.lower()
    for i, row in enumerate(values):
        for cell in row:
            if query_lower in str(cell).lower():
                row_num = i + 1
                print(f"Found in row {row_num}:")
                # Print header if available
                if i > 0 and values[0]:
                    for j, val in enumerate(row):
                        header = values[0][j] if j < len(values[0]) else f"Col {j+1}"
                        print(f"  {header}: {val}")
                else:
                    print(f"  {row}")
                return
    print(f"No row found containing '{query}'")


def copy_sheet(token: str, spreadsheet_id: str, sheet_id: int, dest_spreadsheet_id: str):
    """Copy a sheet to another spreadsheet."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    dest_spreadsheet_id = _extract_id(dest_spreadsheet_id)
    url = f"{SHEETS_BASE}/{spreadsheet_id}/sheets/{sheet_id}:copyTo"
    body = {"destinationSpreadsheetId": dest_spreadsheet_id}
    result = _api_request("POST", url, token, body)
    print(f"Copied sheet to '{result.get('title', '?')}' (ID: {result.get('sheetId', '?')}) in destination spreadsheet")


def format_cells(token: str, spreadsheet_id: str, range_: str,
                 bold: bool = None, italic: bool = None, font_size: int = None,
                 bg_color: str = None):
    """Apply formatting to a cell range."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    # Resolve range to grid coordinates
    sheet_id, grid_range = _parse_a1_to_grid(token, spreadsheet_id, range_)

    cell_format = {}
    fields = []

    text_format = {}
    if bold is not None:
        text_format["bold"] = bold
        fields.append("userEnteredFormat.textFormat.bold")
    if italic is not None:
        text_format["italic"] = italic
        fields.append("userEnteredFormat.textFormat.italic")
    if font_size is not None:
        text_format["fontSize"] = font_size
        fields.append("userEnteredFormat.textFormat.fontSize")
    if text_format:
        cell_format["textFormat"] = text_format

    if bg_color:
        r, g, b = _parse_hex_color(bg_color)
        cell_format["backgroundColor"] = {"red": r, "green": g, "blue": b}
        fields.append("userEnteredFormat.backgroundColor")

    if not fields:
        print("No formatting options specified.")
        return

    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    body = {
        "requests": [{
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    **grid_range,
                },
                "cell": {"userEnteredFormat": cell_format},
                "fields": ",".join(fields),
            }
        }]
    }
    _api_request("POST", url, token, body)
    print(f"Applied formatting to {range_}")


def batch_update_values(token: str, spreadsheet_id: str, data_json: str,
                        input_option: str = "USER_ENTERED"):
    """Write values to multiple ranges in one request.

    data_json format: [{"range": "Sheet1!A1:B2", "values": [["a","b"],["c","d"]]}, ...]
    """
    spreadsheet_id = _extract_id(spreadsheet_id)
    data = json.loads(data_json)
    url = f"{SHEETS_BASE}/{spreadsheet_id}/values:batchUpdate"
    body = {
        "valueInputOption": input_option,
        "data": [{"range": d["range"], "majorDimension": "ROWS", "values": d["values"]} for d in data],
    }
    result = _api_request("POST", url, token, body)
    print(f"Updated {result.get('totalUpdatedCells', 0)} cells across {result.get('totalUpdatedSheets', 0)} sheet(s)")


def insert_rows_cols(token: str, spreadsheet_id: str, sheet_name: str,
                     dimension: str, start_index: int, end_index: int):
    """Insert empty rows or columns at a position."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    sheet_id = _resolve_sheet_id(token, spreadsheet_id, sheet_name)
    if sheet_id is None:
        print(f"Sheet '{sheet_name}' not found.", file=sys.stderr)
        sys.exit(1)
    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    body = {
        "requests": [{
            "insertDimension": {
                "range": {
                    "sheetId": sheet_id,
                    "dimension": dimension.upper(),
                    "startIndex": start_index,
                    "endIndex": end_index,
                },
                "inheritFromBefore": start_index > 0,
            }
        }]
    }
    _api_request("POST", url, token, body)
    count = end_index - start_index
    dim_name = "row" if dimension.upper() == "ROWS" else "column"
    print(f"Inserted {count} {dim_name}(s) at index {start_index} in '{sheet_name}'")


def delete_rows_cols(token: str, spreadsheet_id: str, sheet_name: str,
                     dimension: str, start_index: int, end_index: int):
    """Delete rows or columns from a sheet."""
    spreadsheet_id = _extract_id(spreadsheet_id)
    sheet_id = _resolve_sheet_id(token, spreadsheet_id, sheet_name)
    if sheet_id is None:
        print(f"Sheet '{sheet_name}' not found.", file=sys.stderr)
        sys.exit(1)
    url = f"{SHEETS_BASE}/{spreadsheet_id}:batchUpdate"
    body = {
        "requests": [{
            "deleteDimension": {
                "range": {
                    "sheetId": sheet_id,
                    "dimension": dimension.upper(),
                    "startIndex": start_index,
                    "endIndex": end_index,
                }
            }
        }]
    }
    _api_request("POST", url, token, body)
    count = end_index - start_index
    dim_name = "row" if dimension.upper() == "ROWS" else "column"
    print(f"Deleted {count} {dim_name}(s) from index {start_index} to {end_index} in '{sheet_name}'")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_id(spreadsheet_id_or_url: str) -> str:
    """Extract spreadsheet ID from a full URL or return as-is."""
    if "/" in spreadsheet_id_or_url:
        # https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
        parts = spreadsheet_id_or_url.split("/")
        try:
            d_idx = parts.index("d")
            return parts[d_idx + 1]
        except (ValueError, IndexError):
            pass
    return spreadsheet_id_or_url


def _resolve_sheet_id(token: str, spreadsheet_id: str, sheet_name: str) -> int:
    """Look up a sheet's numeric ID by its title."""
    url = f"{SHEETS_BASE}/{spreadsheet_id}?fields=sheets.properties"
    result = _api_request("GET", url, token)
    for s in result.get("sheets", []):
        if s.get("properties", {}).get("title") == sheet_name:
            return s["properties"]["sheetId"]
    return None


def _parse_a1_to_grid(token: str, spreadsheet_id: str, a1_range: str) -> tuple:
    """Parse A1 notation into (sheet_id, grid_range_dict). Simplified parser."""
    sheet_name = "Sheet1"
    cell_range = a1_range

    if "!" in a1_range:
        sheet_name, cell_range = a1_range.rsplit("!", 1)
        sheet_name = sheet_name.strip("'")

    sheet_id = _resolve_sheet_id(token, spreadsheet_id, sheet_name)
    if sheet_id is None:
        sheet_id = 0

    grid = {}
    if ":" in cell_range:
        start, end = cell_range.split(":")
        sr, sc = _a1_to_indices(start)
        er, ec = _a1_to_indices(end)
        grid["startRowIndex"] = sr
        grid["startColumnIndex"] = sc
        grid["endRowIndex"] = er + 1
        grid["endColumnIndex"] = ec + 1
    else:
        sr, sc = _a1_to_indices(cell_range)
        grid["startRowIndex"] = sr
        grid["startColumnIndex"] = sc
        grid["endRowIndex"] = sr + 1
        grid["endColumnIndex"] = sc + 1

    return sheet_id, grid


def _a1_to_indices(cell_ref: str) -> tuple:
    """Convert A1-style cell reference to (row_index, col_index) (0-based)."""
    col_str = ""
    row_str = ""
    for ch in cell_ref:
        if ch.isalpha():
            col_str += ch.upper()
        else:
            row_str += ch
    col = 0
    for ch in col_str:
        col = col * 26 + (ord(ch) - ord('A') + 1)
    col -= 1  # 0-based
    row = int(row_str) - 1 if row_str else 0
    return row, col


def _parse_hex_color(hex_color: str) -> tuple:
    """Parse #RRGGBB to (r, g, b) floats 0.0-1.0."""
    hex_color = hex_color.lstrip("#")
    if len(hex_color) != 6:
        print(f"Invalid color '{hex_color}'. Use #RRGGBB format.", file=sys.stderr)
        sys.exit(1)
    r = int(hex_color[0:2], 16) / 255.0
    g = int(hex_color[2:4], 16) / 255.0
    b = int(hex_color[4:6], 16) / 255.0
    return r, g, b


def _print_values(values: list, range_label: str):
    """Pretty-print a 2D values array as a table."""
    if not values:
        print(f"{range_label}: (empty)")
        return

    # Calculate column widths
    widths = []
    for row in values:
        for i, cell in enumerate(row):
            cell_str = str(cell)
            if i >= len(widths):
                widths.append(len(cell_str))
            else:
                widths[i] = max(widths[i], len(cell_str))

    # Cap at 50 chars per column
    widths = [min(w, 50) for w in widths]

    print(f"{range_label}:")
    for row_idx, row in enumerate(values):
        line = "  ".join(str(row[i] if i < len(row) else "")[:widths[i]].ljust(widths[i]) for i in range(len(widths)))
        print(f"  {line}")
        # Separator after header row
        if row_idx == 0 and len(values) > 1:
            print(f"  {'  '.join('-' * w for w in widths)}")

    print(f"\n{len(values)} rows")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load_service_account() -> dict:
    raw = os.environ.get("GOOGLE_SERVICE_ACCOUNT_KEY")
    if not raw:
        print("Error: GOOGLE_SERVICE_ACCOUNT_KEY environment variable is not set.", file=sys.stderr)
        print("Set it to the base64-encoded JSON content of your service account key file.", file=sys.stderr)
        sys.exit(1)
    try:
        decoded = base64.b64decode(raw).decode("utf-8")
        sa = json.loads(decoded)
    except Exception:
        try:
            sa = json.loads(raw)
        except json.JSONDecodeError:
            print("Error: GOOGLE_SERVICE_ACCOUNT_KEY is not valid base64-encoded JSON or raw JSON.", file=sys.stderr)
            sys.exit(1)
    required = ["client_email", "private_key"]
    for field in required:
        if field not in sa:
            print(f"Error: service account JSON is missing '{field}' field.", file=sys.stderr)
            sys.exit(1)
    return sa


def main():
    parser = argparse.ArgumentParser(description="Google Sheets REST API client")
    sub = parser.add_subparsers(dest="command")

    # Search
    s = sub.add_parser("search", help="Search for spreadsheets by name")
    s.add_argument("query", help="Search query")
    s.add_argument("--max-results", type=int, default=20, help="Max results (default 20)")

    # Info
    i = sub.add_parser("info", help="Get spreadsheet metadata")
    i.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")

    # List sheets
    ls = sub.add_parser("list-sheets", help="List all sheet tabs")
    ls.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")

    # Get values
    g = sub.add_parser("get", help="Read values from a range")
    g.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    g.add_argument("range", help="A1 notation range (e.g. Sheet1!A1:D10)")
    g.add_argument("--render", choices=["FORMATTED_VALUE", "UNFORMATTED_VALUE", "FORMULA"],
                   default="FORMATTED_VALUE", help="Value render option")

    # Batch get
    bg = sub.add_parser("batch-get", help="Read values from multiple ranges")
    bg.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    bg.add_argument("ranges", nargs="+", help="A1 notation ranges")
    bg.add_argument("--render", choices=["FORMATTED_VALUE", "UNFORMATTED_VALUE", "FORMULA"],
                    default="FORMATTED_VALUE", help="Value render option")

    # Update values
    u = sub.add_parser("update", help="Write values to a range")
    u.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    u.add_argument("range", help="A1 notation range")
    u.add_argument("values", help='JSON 2D array, e.g. \'[["A","B"],["C","D"]]\'')
    u.add_argument("--input", choices=["USER_ENTERED", "RAW"], default="USER_ENTERED",
                   help="Input option (default USER_ENTERED)")

    # Batch update
    bu = sub.add_parser("batch-update", help="Write values to multiple ranges")
    bu.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    bu.add_argument("data", help='JSON array: [{"range":"A1:B2","values":[["a","b"]]}]')
    bu.add_argument("--input", choices=["USER_ENTERED", "RAW"], default="USER_ENTERED",
                    help="Input option (default USER_ENTERED)")

    # Append values
    a = sub.add_parser("append", help="Append rows after existing data")
    a.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    a.add_argument("range", help="A1 notation range (table to append to)")
    a.add_argument("values", help='JSON 2D array of rows to append')
    a.add_argument("--input", choices=["USER_ENTERED", "RAW"], default="USER_ENTERED",
                   help="Input option (default USER_ENTERED)")

    # Clear values
    c = sub.add_parser("clear", help="Clear values in a range")
    c.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    c.add_argument("range", help="A1 notation range to clear")

    # Create spreadsheet
    cr = sub.add_parser("create", help="Create a new spreadsheet")
    cr.add_argument("title", help="Spreadsheet title")

    # Add sheet
    ash = sub.add_parser("add-sheet", help="Add a new sheet tab")
    ash.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    ash.add_argument("title", help="New sheet name")

    # Delete sheet
    ds = sub.add_parser("delete-sheet", help="Delete a sheet tab by ID")
    ds.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    ds.add_argument("sheet_id", type=int, help="Numeric sheet ID (use list-sheets to find)")

    # Find & replace
    fr = sub.add_parser("find-replace", help="Find and replace text")
    fr.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    fr.add_argument("find", help="Text to find")
    fr.add_argument("replace", help="Replacement text")
    fr.add_argument("--match-case", action="store_true", help="Case-sensitive matching")
    fr.add_argument("--regex", action="store_true", help="Treat find as regex")
    fr.add_argument("--sheet", help="Limit to a specific sheet name")

    # Lookup row
    lo = sub.add_parser("lookup", help="Find first row containing a value")
    lo.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    lo.add_argument("query", help="Text to search for")
    lo.add_argument("--range", dest="search_range", help="A1 range to search within")

    # Copy sheet
    cp = sub.add_parser("copy-sheet", help="Copy a sheet to another spreadsheet")
    cp.add_argument("spreadsheet_id", help="Source spreadsheet ID or URL")
    cp.add_argument("sheet_id", type=int, help="Source sheet ID")
    cp.add_argument("dest_spreadsheet_id", help="Destination spreadsheet ID or URL")

    # Format cells
    fmt = sub.add_parser("format", help="Apply formatting to a range")
    fmt.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    fmt.add_argument("range", help="A1 notation range")
    fmt.add_argument("--bold", action="store_true", default=None, help="Bold text")
    fmt.add_argument("--no-bold", action="store_true", help="Remove bold")
    fmt.add_argument("--italic", action="store_true", default=None, help="Italic text")
    fmt.add_argument("--no-italic", action="store_true", help="Remove italic")
    fmt.add_argument("--font-size", type=int, help="Font size")
    fmt.add_argument("--bg-color", help="Background color (#RRGGBB)")

    # Insert rows/columns
    ins = sub.add_parser("insert", help="Insert empty rows or columns")
    ins.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    ins.add_argument("sheet_name", help="Sheet tab name")
    ins.add_argument("dimension", choices=["rows", "columns"], help="What to insert")
    ins.add_argument("start_index", type=int, help="Insert position (0-based)")
    ins.add_argument("count", type=int, help="Number to insert")

    # Delete rows/columns
    dl = sub.add_parser("delete", help="Delete rows or columns")
    dl.add_argument("spreadsheet_id", help="Spreadsheet ID or URL")
    dl.add_argument("sheet_name", help="Sheet tab name")
    dl.add_argument("dimension", choices=["rows", "columns"], help="What to delete")
    dl.add_argument("start_index", type=int, help="Start position (0-based)")
    dl.add_argument("end_index", type=int, help="End position (exclusive, 0-based)")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    sa = _load_service_account()
    token = _get_access_token(sa)

    if args.command == "search":
        search_spreadsheets(token, args.query, args.max_results)
    elif args.command == "info":
        get_spreadsheet_info(token, args.spreadsheet_id)
    elif args.command == "list-sheets":
        list_sheets(token, args.spreadsheet_id)
    elif args.command == "get":
        get_values(token, args.spreadsheet_id, args.range, args.render)
    elif args.command == "batch-get":
        batch_get_values(token, args.spreadsheet_id, args.ranges, args.render)
    elif args.command == "update":
        update_values(token, args.spreadsheet_id, args.range, args.values, args.input)
    elif args.command == "batch-update":
        batch_update_values(token, args.spreadsheet_id, args.data, args.input)
    elif args.command == "append":
        append_values(token, args.spreadsheet_id, args.range, args.values, args.input)
    elif args.command == "clear":
        clear_values(token, args.spreadsheet_id, args.range)
    elif args.command == "create":
        create_spreadsheet(token, args.title)
    elif args.command == "add-sheet":
        add_sheet(token, args.spreadsheet_id, args.title)
    elif args.command == "delete-sheet":
        delete_sheet(token, args.spreadsheet_id, args.sheet_id)
    elif args.command == "find-replace":
        find_replace(token, args.spreadsheet_id, args.find, args.replace,
                     args.match_case, args.regex, args.sheet)
    elif args.command == "lookup":
        lookup_row(token, args.spreadsheet_id, args.query, args.search_range)
    elif args.command == "copy-sheet":
        copy_sheet(token, args.spreadsheet_id, args.sheet_id, args.dest_spreadsheet_id)
    elif args.command == "format":
        bold_val = True if args.bold else (False if args.no_bold else None)
        italic_val = True if args.italic else (False if args.no_italic else None)
        format_cells(token, args.spreadsheet_id, args.range,
                     bold=bold_val, italic=italic_val,
                     font_size=args.font_size, bg_color=args.bg_color)
    elif args.command == "insert":
        insert_rows_cols(token, args.spreadsheet_id, args.sheet_name,
                         args.dimension, args.start_index, args.start_index + args.count)
    elif args.command == "delete":
        delete_rows_cols(token, args.spreadsheet_id, args.sheet_name,
                         args.dimension, args.start_index, args.end_index)


if __name__ == "__main__":
    main()
