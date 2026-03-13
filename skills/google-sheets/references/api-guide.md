# Google Sheets API v4 Reference

Base URL: `https://sheets.googleapis.com/v4/spreadsheets`

All requests require `Authorization: Bearer <access_token>` header.

## Authentication

Exchange a Google Cloud service account JSON key for a short-lived access token:

1. Build a JWT with header `{"alg":"RS256","typ":"JWT"}` and payload containing `iss` (client_email), `scope` (`https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive.readonly`), `aud` (`https://oauth2.googleapis.com/token`), `iat`, `exp` (iat + 3600)
2. Sign with RS256 using the service account's private key
3. POST to `https://oauth2.googleapis.com/token` with `grant_type=urn:ietf:params:oauth:grant_type:jwt-bearer&assertion=<jwt>`
4. Response contains `access_token` (valid 1 hour)

## Endpoints

### Spreadsheet Operations

#### Create Spreadsheet
```
POST /
Body: { "properties": { "title": "My Sheet" } }
```
Response includes `spreadsheetId`, `spreadsheetUrl`, and `properties`.

#### Get Spreadsheet Metadata
```
GET /{spreadsheetId}?fields=spreadsheetId,properties,sheets.properties
```
Returns spreadsheet properties (title, locale, timezone) and sheet tab properties (title, sheetId, gridProperties).

### Values Operations

#### Read Values
```
GET /{spreadsheetId}/values/{range}?valueRenderOption=FORMATTED_VALUE&dateTimeRenderOption=FORMATTED_STRING
```
Response: `{ "range": "Sheet1!A1:D10", "majorDimension": "ROWS", "values": [["a","b"],["c","d"]] }`

#### Batch Read
```
GET /{spreadsheetId}/values:batchGet?ranges=Sheet1!A1:B5&ranges=Sheet2!C1:D5
```
Response: `{ "valueRanges": [{ "range": "...", "values": [...] }, ...] }`

#### Write Values
```
PUT /{spreadsheetId}/values/{range}?valueInputOption=USER_ENTERED
Body: { "range": "Sheet1!A1:B2", "majorDimension": "ROWS", "values": [["Name","Score"],["Alice","95"]] }
```

#### Batch Write
```
POST /{spreadsheetId}/values:batchUpdate
Body: { "valueInputOption": "USER_ENTERED", "data": [{ "range": "A1:B2", "majorDimension": "ROWS", "values": [...] }] }
```

#### Append Values
```
POST /{spreadsheetId}/values/{range}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS
Body: { "majorDimension": "ROWS", "values": [["Bob","87"],["Carol","92"]] }
```

#### Clear Values
```
POST /{spreadsheetId}/values/{range}:clear
Body: {}
```

### Structural Operations (via batchUpdate)

All structural changes use a single endpoint:
```
POST /{spreadsheetId}:batchUpdate
Body: { "requests": [ ... ] }
```

#### Add Sheet
```json
{ "addSheet": { "properties": { "title": "New Tab" } } }
```

#### Delete Sheet
```json
{ "deleteSheet": { "sheetId": 12345 } }
```

#### Insert Rows/Columns
```json
{
  "insertDimension": {
    "range": { "sheetId": 0, "dimension": "ROWS", "startIndex": 5, "endIndex": 8 },
    "inheritFromBefore": true
  }
}
```

#### Delete Rows/Columns
```json
{
  "deleteDimension": {
    "range": { "sheetId": 0, "dimension": "COLUMNS", "startIndex": 2, "endIndex": 5 }
  }
}
```

#### Find & Replace
```json
{
  "findReplace": {
    "find": "old text",
    "replacement": "new text",
    "allSheets": true,
    "matchCase": false,
    "searchByRegex": false
  }
}
```

#### Format Cells
```json
{
  "repeatCell": {
    "range": { "sheetId": 0, "startRowIndex": 0, "endRowIndex": 1, "startColumnIndex": 0, "endColumnIndex": 4 },
    "cell": {
      "userEnteredFormat": {
        "textFormat": { "bold": true, "fontSize": 14 },
        "backgroundColor": { "red": 0.26, "green": 0.52, "blue": 0.96 }
      }
    },
    "fields": "userEnteredFormat.textFormat.bold,userEnteredFormat.textFormat.fontSize,userEnteredFormat.backgroundColor"
  }
}
```

### Copy Sheet
```
POST /{spreadsheetId}/sheets/{sheetId}:copyTo
Body: { "destinationSpreadsheetId": "dest_id" }
```

### Search Spreadsheets (Drive API)
```
GET https://www.googleapis.com/drive/v3/files?q=mimeType='application/vnd.google-apps.spreadsheet' and name contains 'query'&fields=files(id,name,modifiedTime,owners)&orderBy=modifiedTime desc
```

## Value Render Options

| Option | Description |
|--------|-------------|
| `FORMATTED_VALUE` | Values as displayed in the UI (default) |
| `UNFORMATTED_VALUE` | Raw numeric values without formatting |
| `FORMULA` | Shows formulas instead of computed values |

## Value Input Options

| Option | Description |
|--------|-------------|
| `USER_ENTERED` | Parses input as if typed by a user (formulas, dates auto-detected) |
| `RAW` | Stores values as literal strings (no parsing) |

## A1 Notation

| Pattern | Description |
|---------|-------------|
| `Sheet1!A1:D10` | Fixed range on Sheet1 |
| `Sheet1!A:B` | Entire columns A and B |
| `Sheet1!1:3` | Entire rows 1 through 3 |
| `Sheet1` | Entire sheet |
| `A1:D10` | Range on the first sheet |
| `'My Sheet'!A1:B5` | Sheet name with spaces (quoted) |

## Rate Limits

| Quota | Limit |
|-------|-------|
| Read requests | 300 per minute per project |
| Write requests | 60 per minute per project |
| Per-user reads | 60 per minute per user |
| Per-user writes | 60 per minute per user |

Use batch operations (`batch-get`, `batch-update`) to reduce the number of API calls when working with multiple ranges.
