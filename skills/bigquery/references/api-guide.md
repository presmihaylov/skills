# BigQuery REST API v2 Reference

Base URL: `https://bigquery.googleapis.com/bigquery/v2`

All requests require `Authorization: Bearer <access_token>` header.

## Authentication

Exchange a Google Cloud service account JSON key for a short-lived access token:

1. Build a JWT with header `{"alg":"RS256","typ":"JWT"}` and payload containing `iss` (client_email), `scope` (`https://www.googleapis.com/auth/bigquery`), `aud` (`https://oauth2.googleapis.com/token`), `iat`, `exp` (iat + 3600)
2. Sign with RS256 using the service account's private key
3. POST to `https://oauth2.googleapis.com/token` with `grant_type=urn:ietf:params:oauth:grant_type:jwt-bearer&assertion=<jwt>`
4. Response contains `access_token` (valid 1 hour)

## Endpoints

### List Datasets
```
GET /projects/{projectId}/datasets
```
Response: `{ "datasets": [{ "datasetReference": { "datasetId": "..." }, "location": "US" }] }`

### List Tables
```
GET /projects/{projectId}/datasets/{datasetId}/tables
```
Response: `{ "tables": [{ "tableReference": { "tableId": "..." }, "type": "TABLE", "numRows": "1234" }] }`

### Get Table Metadata & Schema
```
GET /projects/{projectId}/datasets/{datasetId}/tables/{tableId}
```
Response includes `schema.fields[]` array with `name`, `type`, `mode`, `description`, and nested `fields` for RECORD types.

Field types: `STRING`, `INTEGER`, `FLOAT`, `BOOLEAN`, `TIMESTAMP`, `DATE`, `DATETIME`, `TIME`, `BYTES`, `NUMERIC`, `BIGNUMERIC`, `GEOGRAPHY`, `RECORD`, `JSON`

Modes: `NULLABLE`, `REQUIRED`, `REPEATED`

### Run Query (Synchronous)
```
POST /projects/{projectId}/queries
```
Request body:
```json
{
  "query": "SELECT ...",
  "useLegacySql": false,
  "maxResults": 100,
  "dryRun": false
}
```

Response:
- `jobComplete`: boolean — if false, poll with getQueryResults
- `schema.fields[]`: column definitions
- `rows[].f[].v`: cell values (all returned as strings)
- `totalRows`: total result count
- `totalBytesProcessed`: bytes scanned

For dry runs: only `totalBytesProcessed` is meaningful — use to estimate cost before running expensive queries.

### Get Query Results (Polling)
```
GET /projects/{projectId}/queries/{jobId}?maxResults=100&pageToken=...
```
Use when `jobComplete` is false on the initial query response. Poll until `jobComplete` is true.

## Cost Estimation

BigQuery charges per bytes scanned. Use `--dry-run` to check before running large queries.

| Tier | Price |
|------|-------|
| On-demand | $6.25 per TB scanned |
| First 1 TB/month | Free |

## Common Patterns

### Explore a new dataset
```bash
python scripts/bigquery_api.py list-datasets
python scripts/bigquery_api.py list-tables <dataset>
python scripts/bigquery_api.py get-schema <dataset> <table>
```

### Check query cost before running
```bash
python scripts/bigquery_api.py query "SELECT * FROM dataset.table" --dry-run
python scripts/bigquery_api.py query "SELECT * FROM dataset.table" --max-results 10
```

### Sample data from a table
```sql
SELECT * FROM `project.dataset.table` LIMIT 10
```

### Count rows
```sql
SELECT COUNT(*) as total FROM `project.dataset.table`
```

### Get table info via INFORMATION_SCHEMA
```sql
SELECT table_name, row_count, size_bytes
FROM `project.dataset.INFORMATION_SCHEMA.TABLE_STORAGE`
ORDER BY size_bytes DESC
```
