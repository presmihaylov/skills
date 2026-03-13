---
name: bigquery
description: Query and explore Google BigQuery datasets using the REST API. Use this skill when the user asks to run SQL queries against BigQuery, explore datasets/tables, check table schemas, or estimate query costs. Triggers on BigQuery, BQ, or data warehouse requests.
---

# BigQuery

## Overview

Query and explore Google BigQuery directly via the REST API. No SDK or `bq` CLI needed — the bundled script handles service account authentication and calls the BigQuery v2 REST endpoints using only Python stdlib.

## Quick Decision Tree

```
What do you need?
│
├── Explore what data exists
│   └── python scripts/bigquery_api.py list-datasets
│   └── python scripts/bigquery_api.py list-tables <dataset>
│
├── Understand a table's structure
│   └── python scripts/bigquery_api.py get-schema <dataset> <table>
│
├── Run a SQL query
│   └── python scripts/bigquery_api.py query "SELECT ..." --max-results 100
│
└── Estimate query cost before running
    └── python scripts/bigquery_api.py query "SELECT ..." --dry-run
```

## Environment Setup

```bash
# Required — set to the base64-encoded JSON content of a Google Cloud service account key
# Generate with: cat service-account.json | base64 -w 0
GOOGLE_SERVICE_ACCOUNT_KEY='eyJ0eXBlIjoic2VydmljZV9hY2NvdW50IiwicHJvamVjdF9pZCI6Ii4uLiIsInByaXZhdGVfa2V5IjoiLi4uIiwiY2xpZW50X2VtYWlsIjoiLi4uIn0='
```

The value must be the base64-encoded version of the full service account JSON key file. This avoids shell escaping issues with raw JSON containing special characters.

The service account needs the `BigQuery User` role (`roles/bigquery.user`) at minimum. For write access, add `BigQuery Data Editor`.

Generate a key: Google Cloud Console > IAM & Admin > Service Accounts > Keys > Add Key > JSON. Then base64-encode it before setting the env var.

## Common Usage

### List Datasets
```bash
python scripts/bigquery_api.py list-datasets
```

### List Tables in a Dataset
```bash
python scripts/bigquery_api.py list-tables my_dataset
```

### Get Table Schema
```bash
python scripts/bigquery_api.py get-schema my_dataset my_table
```

### Run a Query
```bash
python scripts/bigquery_api.py query "SELECT * FROM my_dataset.my_table LIMIT 10"
```

### Limit Results
```bash
python scripts/bigquery_api.py query "SELECT * FROM my_dataset.my_table" --max-results 50
```

### Dry Run (Cost Estimation)
```bash
python scripts/bigquery_api.py query "SELECT * FROM my_dataset.big_table" --dry-run
```
Returns estimated bytes to be processed without actually running the query. Useful before running expensive queries on large tables.

## Schema Discovery Workflow

When working with an unfamiliar BigQuery project, follow this sequence to build context:

1. `list-datasets` — see what datasets exist
2. `list-tables <dataset>` — see tables and row counts
3. `get-schema <dataset> <table>` — inspect column names, types, and descriptions
4. `query "SELECT * FROM dataset.table LIMIT 5"` — sample actual data

For projects with many tables, use INFORMATION_SCHEMA to get an overview:
```bash
python scripts/bigquery_api.py query "SELECT table_name, row_count, size_bytes FROM project.dataset.INFORMATION_SCHEMA.TABLE_STORAGE ORDER BY size_bytes DESC"
```

## Query Best Practices

- Always include a `LIMIT` clause when exploring unfamiliar tables
- Use `--dry-run` before running queries on large tables to check cost
- Prefer `SELECT specific_columns` over `SELECT *` to reduce bytes scanned
- Use partitioned column filters (e.g., `WHERE date >= '2026-01-01'`) to limit scan scope
- BigQuery charges by bytes scanned ($6.25/TB on-demand, first 1 TB/month free)

## Long-Running Queries

The script handles async queries automatically. If BigQuery returns `jobComplete: false`, the script polls for results with a 2-second interval and a 120-second timeout. No manual intervention needed for queries that take a few seconds to complete.

## Security Notes

- The `GOOGLE_SERVICE_ACCOUNT_KEY` contains a base64-encoded private key — store it in a vault, never in source control
- The script exchanges the key for a short-lived access token (1 hour) on each invocation
- No tokens or keys are cached to disk
- All API calls use HTTPS
- The script is read-only by default (queries only, no data modification)

## Troubleshooting

### "GOOGLE_SERVICE_ACCOUNT_KEY is not set"
Set the environment variable to the base64-encoded JSON content of the service account key file (`cat key.json | base64 -w 0`). On Nairi, store it as a vault secret.

### "403 Access Denied"
The service account lacks BigQuery permissions. Assign `BigQuery User` role in Google Cloud IAM.

### "404 Not found: Dataset/Table"
Check dataset and table names with `list-datasets` and `list-tables`. Names are case-sensitive.

### Query timeout
Queries over 120 seconds will time out. Add filters or `LIMIT` to reduce the result set, or break the query into smaller parts.

### "openssl signing failed"
The script needs either the `cryptography` Python package or `openssl` CLI to sign JWTs. Most systems have at least one. Install with `pip install cryptography` if needed.

## Resources

- **scripts/bigquery_api.py** — CLI tool for all BigQuery operations
- **references/api-guide.md** — BigQuery REST API v2 endpoint reference, auth details, and common query patterns
