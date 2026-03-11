---
name: intercom
description: "Query and browse Intercom conversations, contacts, tickets, and tags via the Intercom REST API. This skill should be used when a user wants to search conversations, look up contacts, find tickets, list tags, or read full conversation threads in their Intercom workspace. Requires an Intercom API access token stored as INTERCOM_API_TOKEN in the environment or vault."
---

# Intercom API Skill

Search and browse an Intercom workspace directly through the REST API (v2.11).

## Authentication

The skill requires an Intercom API access token. Resolve the token in this order:

1. `INTERCOM_API_TOKEN` environment variable
2. If not set, ask the user to provide one

To obtain a token: **Intercom > Settings > Integrations > Developer Hub** — create
an internal integration and enable read permissions for conversations, contacts,
and tickets.

## Available Operations

| Operation | Description |
|-----------|-------------|
| **Search conversations** | Find conversations by date, state, assignee, contact, tag, source body, priority, AI agent participation, and more |
| **Get conversation** | Retrieve a full conversation with all message parts |
| **Search contacts** | Find contacts by email, name, role, location, custom attributes, and more |
| **Search tickets** | Find tickets by state, type, assignee, date, custom attributes |
| **List tags** | List all tags in the workspace |

## How to Use

All API calls go through the helper script `scripts/intercom_api.sh`. It handles
auth headers, pagination, and error formatting.

### Quick Reference

```bash
# Search conversations (e.g. open conversations from the last 7 days)
scripts/intercom_api.sh search-conversations \
  '{"operator":"AND","value":[{"field":"state","operator":"=","value":"open"},{"field":"created_at","operator":">","value":"UNIX_TIMESTAMP"}]}'

# Single-field search (e.g. all conversations with a specific contact)
scripts/intercom_api.sh search-conversations \
  '{"field":"contact_ids","operator":"=","value":"CONTACT_ID"}'

# Get a single conversation with all parts
scripts/intercom_api.sh get-conversation CONVERSATION_ID

# Get conversation in plain text (no HTML)
scripts/intercom_api.sh get-conversation CONVERSATION_ID plaintext

# Search contacts by email
scripts/intercom_api.sh search-contacts \
  '{"field":"email","operator":"=","value":"user@example.com"}'

# Search tickets (e.g. open tickets)
scripts/intercom_api.sh search-tickets \
  '{"field":"state","operator":"=","value":"open"}'

# List all tags
scripts/intercom_api.sh list-tags
```

### Pagination

For search operations, pass the `starting_after` cursor as a second argument and
per_page as a third argument to paginate through results:

```bash
# First page (10 results)
scripts/intercom_api.sh search-conversations '{"field":"state","operator":"=","value":"open"}' "" 10

# Next page (use starting_after from previous response's pages.next.starting_after)
scripts/intercom_api.sh search-conversations '{"field":"state","operator":"=","value":"open"}' "WzE2OTk0OTMwNjYsMTM1LDJd" 10
```

### Per-page Limits

Default is 20 results per page. Max is 150 for conversations/tickets, 50 for contacts.

## Query Format

The Intercom search API uses structured queries. See `references/query_format.md`
for the full specification including operators, nesting, and field lists.

### Two Query Forms

**Single filter** — match one field:
```json
{"field": "state", "operator": "=", "value": "open"}
```

**Compound filter** — combine multiple conditions with AND/OR:
```json
{
  "operator": "AND",
  "value": [
    {"field": "state", "operator": "=", "value": "open"},
    {"field": "created_at", "operator": ">", "value": "1709251200"}
  ]
}
```

Compound filters support up to 2 levels of nesting and 15 filters per group.

### Important Notes

- All date values must be **UNIX timestamps** (seconds), passed as strings
- `source.body` searches are **per-word**, not substring — search for `"support"` not `"I need support"`
- Contact timestamps have **day granularity** — searching `created_at > 1577869200` (Jan 1 9am) is interpreted as `> 1577836800` (Jan 1 midnight)
- Newly created contacts may take a few minutes to appear in search results
- Conversation search results do NOT include message parts — call `get-conversation` for the full thread
- Max 500 conversation parts returned per conversation

### Searchable Fields

Detailed field lists for each endpoint are in `references/query_format.md`. The
most commonly used fields:

**Conversations:** `state`, `open`, `created_at`, `updated_at`, `source.body`,
`source.author.email`, `contact_ids`, `admin_assignee_id`, `team_assignee_id`,
`tag_ids`, `priority`, `ai_agent_participated`

**Contacts:** `email`, `name`, `role`, `phone`, `external_id`, `created_at`,
`last_seen_at`, `tag_id`, `segment_id`, `custom_attributes.{name}`

**Tickets:** `state`, `title`, `description`, `ticket_type_id`, `created_at`,
`admin_assignee_id`, `team_assignee_id`, `ticket_attribute.{id}`

## Operators

| Operator | Types | Description |
|----------|-------|-------------|
| `=` | All | Equals |
| `!=` | All | Not equals |
| `IN` | All | In list (value is array) |
| `NIN` | All | Not in list (value is array) |
| `>` | Int, Date | Greater than or equal |
| `<` | Int, Date | Less than or equal |
| `~` | String | Contains |
| `!~` | String | Does not contain |
| `^` | String | Starts with |
| `$` | String | Ends with |

## Common Workflows

### Find recent conversations about a topic
```bash
# Get unix timestamp for 7 days ago
TS=$(date -d '7 days ago' +%s)

# Search conversations created in the last 7 days containing "billing" in source body
scripts/intercom_api.sh search-conversations \
  "{\"operator\":\"AND\",\"value\":[{\"field\":\"created_at\",\"operator\":\">\",\"value\":\"$TS\"},{\"field\":\"source.body\",\"operator\":\"~\",\"value\":\"billing\"}]}"
```

### Find a contact and their conversations
```bash
# Find the contact
scripts/intercom_api.sh search-contacts \
  '{"field":"email","operator":"=","value":"user@example.com"}'

# Use the contact ID from the response to find their conversations
scripts/intercom_api.sh search-conversations \
  '{"field":"contact_ids","operator":"=","value":"CONTACT_ID_FROM_ABOVE"}'
```

### Find unassigned open conversations
```bash
scripts/intercom_api.sh search-conversations \
  '{"operator":"AND","value":[{"field":"state","operator":"=","value":"open"},{"field":"admin_assignee_id","operator":"=","value":"0"}]}'
```

### Read a full conversation thread
```bash
# Search for the conversation first
scripts/intercom_api.sh search-conversations \
  '{"field":"source.body","operator":"~","value":"refund"}'

# Then get the full thread with all parts in plain text
scripts/intercom_api.sh get-conversation 12345 plaintext
```
