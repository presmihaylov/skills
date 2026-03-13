---
name: google-sheets
description: Read, write, and manage Google Sheets spreadsheets using the REST API. Use this skill when the user asks to read or update spreadsheet data, search for spreadsheets, manage sheet tabs, or format cells. Triggers on Google Sheets, spreadsheet, or sheet-related requests.
allowed-tools: Bash
---

# Google Sheets

## Overview

Read, write, and manage Google Sheets directly via the REST API. No SDK, no Composio, no MCP proxy needed — the bundled script handles service account authentication and calls the Sheets API v4 and Drive API v3 using only Python stdlib.

## Quick Decision Tree

```
What do you need?
│
├── Find a spreadsheet
│   └── python scripts/sheets_api.py search "quarterly report"
│
├── Explore a spreadsheet's structure
│   └── python scripts/sheets_api.py info <spreadsheet_id>
│   └── python scripts/sheets_api.py list-sheets <spreadsheet_id>
│
├── Read data
│   └── python scripts/sheets_api.py get <id> Sheet1!A1:D10
│   └── python scripts/sheets_api.py batch-get <id> Sheet1!A:B Sheet2!C:D
│
├── Write data
│   └── python scripts/sheets_api.py update <id> Sheet1!A1:B2 '[["Name","Score"],["Alice","95"]]'
│   └── python scripts/sheets_api.py append <id> Sheet1!A:B '[["Bob","87"]]'
│   └── python scripts/sheets_api.py batch-update <id> '[{"range":"A1:B2","values":[["a","b"]]}]'
│
├── Manage sheets
│   └── python scripts/sheets_api.py create "New Spreadsheet"
│   └── python scripts/sheets_api.py add-sheet <id> "New Tab"
│   └── python scripts/sheets_api.py delete-sheet <id> <sheet_id>
│   └── python scripts/sheets_api.py copy-sheet <id> <sheet_id> <dest_id>
│
├── Modify structure
│   └── python scripts/sheets_api.py insert <id> Sheet1 rows 5 3
│   └── python scripts/sheets_api.py delete <id> Sheet1 columns 2 5
│
├── Find & replace
│   └── python scripts/sheets_api.py find-replace <id> "old" "new"
│   └── python scripts/sheets_api.py lookup <id> "search term"
│
└── Format cells
    └── python scripts/sheets_api.py format <id> Sheet1!A1:D1 --bold --bg-color "#4285F4"
```

## Environment Setup

This skill requires one environment variable:

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_SERVICE_ACCOUNT_KEY` | Yes | Base64-encoded JSON content of a Google Cloud service account key |

### Step-by-step setup

1. **Create a service account** in Google Cloud Console (IAM & Admin > Service Accounts)
2. **Enable APIs** in the same GCP project:
   - Google Sheets API (required)
   - Google Drive API (required for the `search` command)
3. **Create a JSON key** for the service account (Keys > Add Key > JSON) — this downloads a `.json` file
4. **Base64-encode** the key file:
   ```bash
   cat service-account.json | base64 -w 0
   ```
5. **Set the env var** on your Nairi agent container:
   - Go to the Nairi dashboard > your agent > Environment Variables
   - Add `GOOGLE_SERVICE_ACCOUNT_KEY` with the base64-encoded value
   - Or store it as a vault secret and reference it
6. **Share target spreadsheets** with the service account email (found in the JSON key as `client_email`, looks like `name@project.iam.gserviceaccount.com`) — add it as an Editor for read/write access

## Common Usage

### Search for Spreadsheets
```bash
python scripts/sheets_api.py search "quarterly report"
python scripts/sheets_api.py search "budget" --max-results 5
```

### Get Spreadsheet Info
```bash
python scripts/sheets_api.py info 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms
# Also accepts full URLs:
python scripts/sheets_api.py info "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms/edit"
```

### List Sheet Tabs
```bash
python scripts/sheets_api.py list-sheets <spreadsheet_id>
```

### Read Values
```bash
# Single range
python scripts/sheets_api.py get <id> Sheet1!A1:D10

# Multiple ranges in one call
python scripts/sheets_api.py batch-get <id> Sheet1!A1:B5 Sheet2!C1:D5

# Get formulas instead of computed values
python scripts/sheets_api.py get <id> Sheet1!A1:D10 --render FORMULA
```

### Write Values
```bash
# Overwrite a range
python scripts/sheets_api.py update <id> Sheet1!A1:B2 '[["Name","Score"],["Alice","95"]]'

# Append rows after existing data
python scripts/sheets_api.py append <id> Sheet1!A:B '[["Bob","87"],["Carol","92"]]'

# Write to multiple ranges at once
python scripts/sheets_api.py batch-update <id> '[{"range":"Sheet1!A1:B2","values":[["a","b"],["c","d"]]},{"range":"Sheet2!A1","values":[["x"]]}]'

# Write raw values (no formula parsing)
python scripts/sheets_api.py update <id> Sheet1!A1:B1 '[["=SUM(A2:A10)","text"]]' --input RAW
```

### Clear Values
```bash
python scripts/sheets_api.py clear <id> Sheet1!A1:D10
```

### Create & Manage Spreadsheets
```bash
# Create new spreadsheet
python scripts/sheets_api.py create "My New Spreadsheet"

# Add a sheet tab
python scripts/sheets_api.py add-sheet <id> "Q1 Data"

# Delete a sheet tab (use list-sheets to find the numeric ID)
python scripts/sheets_api.py delete-sheet <id> 12345

# Copy a sheet to another spreadsheet
python scripts/sheets_api.py copy-sheet <source_id> <sheet_id> <dest_id>
```

### Insert & Delete Rows/Columns
```bash
# Insert 3 empty rows at row 6 (0-based index 5)
python scripts/sheets_api.py insert <id> Sheet1 rows 5 3

# Insert 2 columns at column C (0-based index 2)
python scripts/sheets_api.py insert <id> Sheet1 columns 2 2

# Delete rows 3-5 (0-based: index 2 to 5, exclusive end)
python scripts/sheets_api.py delete <id> Sheet1 rows 2 5

# Delete columns D-F (0-based: index 3 to 6)
python scripts/sheets_api.py delete <id> Sheet1 columns 3 6
```

### Find & Replace
```bash
# Simple find & replace across all sheets
python scripts/sheets_api.py find-replace <id> "old text" "new text"

# Case-sensitive, regex, limited to one sheet
python scripts/sheets_api.py find-replace <id> "Q[1-4] 202[0-9]" "FY2026" --regex --match-case --sheet "Summary"
```

### Lookup a Row
```bash
# Find the first row containing a value (case-insensitive)
python scripts/sheets_api.py lookup <id> "alice@example.com"

# Search within a specific range
python scripts/sheets_api.py lookup <id> "alice" --range "Sheet1!A:E"
```

### Format Cells
```bash
# Bold the header row
python scripts/sheets_api.py format <id> Sheet1!A1:D1 --bold

# Set font size and background color
python scripts/sheets_api.py format <id> Sheet1!A1:D1 --font-size 14 --bg-color "#4285F4"

# Italicize a range
python scripts/sheets_api.py format <id> Sheet1!B2:B10 --italic
```

## Data Discovery Workflow

When working with an unfamiliar spreadsheet:

1. `search "keyword"` — find the spreadsheet
2. `info <id>` — see title, sheets, dimensions
3. `list-sheets <id>` — see all tabs with row/column counts
4. `get <id> Sheet1!A1:E5` — sample the first few rows
5. `get <id> Sheet1!A1:A1 --render FORMULA` — check if formulas are used

## Input Format

- **Spreadsheet ID**: the long alphanumeric string from the URL, or the full Google Sheets URL
- **Range**: A1 notation — `Sheet1!A1:D10`, `Sheet1!A:B` (full columns), `Sheet1` (entire sheet)
- **Values**: JSON 2D array — `[["row1col1","row1col2"],["row2col1","row2col2"]]`
- **Value input option**: `USER_ENTERED` (default, parses formulas/dates) or `RAW` (literal strings)

## Security Notes

- The `GOOGLE_SERVICE_ACCOUNT_KEY` contains a base64-encoded private key — store it in a vault, never in source control
- The script exchanges the key for a short-lived access token (1 hour) on each invocation
- No tokens or keys are cached to disk
- All API calls use HTTPS
- The service account can only access spreadsheets explicitly shared with its email address

## Troubleshooting

### "GOOGLE_SERVICE_ACCOUNT_KEY is not set"
Set the environment variable to the base64-encoded JSON content of the service account key file (`cat key.json | base64 -w 0`). On Nairi, store it as a vault secret.

### "403 Forbidden"
The service account lacks access. Either share the spreadsheet with the service account email, or enable the Sheets/Drive API in the Google Cloud project.

### "404 Not Found"
Check the spreadsheet ID. Use `search` to find spreadsheets, or copy the ID from the URL.

### "400 Unable to parse range"
Check A1 notation syntax. Sheet names with spaces need quotes in the URL but the script handles this. Examples: `Sheet1!A1:D10`, `'My Sheet'!A1:B5`.

### "openssl signing failed"
The script needs either the `cryptography` Python package or `openssl` CLI to sign JWTs. Most systems have at least one. Install with `pip install cryptography` if needed.

## Resources

- **scripts/sheets_api.py** — CLI tool for all Google Sheets operations
- **references/api-guide.md** — Sheets API v4 endpoint reference and authentication details
