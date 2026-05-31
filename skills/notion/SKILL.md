---
name: notion
description: "Full read/write access to a Notion workspace via the Notion REST API (version 2025-09-03 / Data Source Edition). Mirrors the official Notion MCP server's 22-tool surface. Use this skill when the user wants to search Notion, read/create/update pages, query data sources, append or modify blocks, manage comments, list users, or operate on databases. Requires NOTION_API_KEY env var (internal integration token, ntn_... prefix)."
---

# Notion Skill

Wraps the Notion REST API (`https://api.notion.com/v1/...`, version `2025-09-03`) with one CLI script (`scripts/notion_api.sh`) that mirrors the 22 tools exposed by the official [Notion MCP server](https://github.com/makenotion/notion-mcp-server).

## Authentication

Requires the `NOTION_API_KEY` environment variable (Notion internal integration token, usually `ntn_...` or `secret_...`).

To create one: **Notion → Settings → Connections → Develop or manage integrations → New integration**. Then share the relevant pages/databases with the integration from each page's "..." menu — pages the integration was not given access to will return 404.

## API Version Note

This skill uses Notion API version `2025-09-03` (Data Source Edition), which matches what the official MCP server uses. The key change vs. older versions: a Notion "database" now wraps one or more "data sources." For most workspaces created before 2025 there is exactly one data source per database, and `query-data-source` replaces the old `post-database-query`.

## Tool Inventory

All 22 commands (matches official MCP tool names — `operationId` from Notion's OpenAPI spec):

### Users
| Command | HTTP | Description |
|---------|------|-------------|
| `get-self` | `GET /users/me` | Retrieve the bot user attached to the API key |
| `get-user <user_id>` | `GET /users/{id}` | Retrieve a specific user |
| `get-users` | `GET /users` | List all users in the workspace |

### Search
| Command | HTTP | Description |
|---------|------|-------------|
| `post-search <body_json>` | `POST /search` | Search pages/data sources by title |

### Pages
| Command | HTTP | Description |
|---------|------|-------------|
| `retrieve-a-page <page_id>` | `GET /pages/{id}` | Retrieve a page (properties only, no body) |
| `post-page <body_json>` | `POST /pages` | Create a new page |
| `patch-page <page_id> <body_json>` | `PATCH /pages/{id}` | Update page properties (and/or archive) |
| `retrieve-a-page-property <page_id> <property_id>` | `GET /pages/{id}/properties/{prop_id}` | Retrieve a single page property value |
| `move-page <page_id> <body_json>` | `POST /pages/{id}/move` | Move a page to a new parent |

### Blocks
| Command | HTTP | Description |
|---------|------|-------------|
| `retrieve-a-block <block_id>` | `GET /blocks/{id}` | Retrieve a single block |
| `update-a-block <block_id> <body_json>` | `PATCH /blocks/{id}` | Update a block's content |
| `delete-a-block <block_id>` | `DELETE /blocks/{id}` | Delete (archive) a block |
| `get-block-children <block_id> [start_cursor] [page_size]` | `GET /blocks/{id}/children` | List children of a block (or page) |
| `patch-block-children <block_id> <body_json>` | `PATCH /blocks/{id}/children` | Append child blocks |

### Comments
| Command | HTTP | Description |
|---------|------|-------------|
| `retrieve-a-comment <block_id> [start_cursor] [page_size]` | `GET /comments?block_id=...` | List comments on a page or block |
| `create-a-comment <body_json>` | `POST /comments` | Create a comment on a page or in a discussion |

### Data Sources (the new "database query" surface)
| Command | HTTP | Description |
|---------|------|-------------|
| `query-data-source <data_source_id> <body_json>` | `POST /data_sources/{id}/query` | Query (filter/sort/paginate) a data source |
| `retrieve-a-data-source <data_source_id>` | `GET /data_sources/{id}` | Retrieve a data source schema |
| `update-a-data-source <data_source_id> <body_json>` | `PATCH /data_sources/{id}` | Update data source schema |
| `create-a-data-source <body_json>` | `POST /data_sources` | Create a new data source under a database |
| `list-data-source-templates <data_source_id>` | `GET /data_sources/{id}/templates` | List page templates for a data source |

### Databases (wrapper for one-or-more data sources)
| Command | HTTP | Description |
|---------|------|-------------|
| `retrieve-a-database <database_id>` | `GET /databases/{id}` | Retrieve a database (includes its `data_sources` list) |

## Quick Usage

```bash
# Identify the integration's bot user (smoke test the token)
scripts/notion_api.sh get-self

# Find a page by title
scripts/notion_api.sh post-search '{"query":"CRM","filter":{"property":"object","value":"page"}}'

# Read a page's properties
scripts/notion_api.sh retrieve-a-page 1234abcd-1234-1234-1234-1234567890ab

# Read a page's body (blocks)
scripts/notion_api.sh get-block-children 1234abcd-1234-1234-1234-1234567890ab

# Append a paragraph block to a page
scripts/notion_api.sh patch-block-children PAGE_ID '{
  "children":[
    {"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"hello from nairi"}}]}}
  ]
}'

# Create a new page under a parent page
scripts/notion_api.sh post-page '{
  "parent":{"page_id":"PARENT_PAGE_ID"},
  "properties":{"title":[{"text":{"content":"My new page"}}]}
}'

# Query a data source (the new "database query")
# Step 1: get the database to find its data_sources[].id
scripts/notion_api.sh retrieve-a-database DATABASE_ID
# Step 2: query that data source
scripts/notion_api.sh query-data-source DATA_SOURCE_ID '{
  "filter":{"property":"Status","status":{"equals":"In progress"}},
  "page_size":25
}'
```

## Common Workflows

### Find the data_source_id for a legacy database
Older API versions queried `/v1/databases/{id}/query` directly. In 2025-09-03 you query a data source instead. Workflow:

```bash
scripts/notion_api.sh retrieve-a-database DATABASE_ID | jq -r '.data_sources[0].id'
scripts/notion_api.sh query-data-source <that_id> '{...filter...}'
```

For most databases there's a single data source whose ID is the same as the database ID — but always confirm by calling `retrieve-a-database` first.

### Read a full page (properties + body)
```bash
scripts/notion_api.sh retrieve-a-page PAGE_ID         # properties
scripts/notion_api.sh get-block-children PAGE_ID      # body
```

To recursively read nested blocks, call `get-block-children` for any returned block whose `has_children` is true.

### Pagination
List endpoints (`get-users`, `get-block-children`, `retrieve-a-comment`, `query-data-source`, `post-search`) return `has_more` and `next_cursor`. Pass `next_cursor` as the `start_cursor` parameter (or in the body for POST endpoints) to get the next page.

## Output Format

All commands return JSON (raw response from Notion, formatted with `jq`). Non-2xx responses print the error to stderr and exit non-zero.

## Notes / Gotchas

- **Page IDs**: Notion accepts page IDs in both hyphenated UUID and unhyphenated 32-char form. URLs use the unhyphenated form. Either works.
- **Sharing**: Integrations only see pages explicitly shared with them. A 404 usually means the page isn't shared with the integration, not that it doesn't exist.
- **Rate limits**: Notion enforces ~3 requests/second per integration. Bursts above that return 429.
- **Title property**: When creating a page, the title property's name depends on the parent. For pages under another page, use `title`. For pages in a database, use whatever the database's title property is named (often `Name` or `title`).
- **Archive vs delete**: There's no hard delete in the Notion API. `delete-a-block` and the `archived: true` flag on `patch-page` both archive; `archived: false` restores.
- **Sensitive token**: `NOTION_API_KEY` grants full read/write to every page the integration has access to. Store it in a vault, never inline in code.
