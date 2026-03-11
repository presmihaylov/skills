# Intercom Search Query Format Reference

Base URL: `https://api.intercom.io`
API Version: `2.11` (set via `Intercom-Version` header)

## Query Structure

All search endpoints (`/conversations/search`, `/contacts/search`, `/tickets/search`)
accept the same query structure in the request body:

```json
{
  "query": { ... },
  "pagination": {
    "per_page": 25,
    "starting_after": "cursor-from-previous-response"
  }
}
```

## Single Filter

```json
{
  "query": {
    "field": "created_at",
    "operator": ">",
    "value": "1306054154"
  }
}
```

## Compound Filter (AND/OR)

```json
{
  "query": {
    "operator": "AND",
    "value": [
      { "field": "created_at", "operator": ">", "value": "1306054154" },
      { "field": "state", "operator": "=", "value": "open" }
    ]
  }
}
```

## Nested Compound Filter

```json
{
  "query": {
    "operator": "AND",
    "value": [
      {
        "operator": "OR",
        "value": [
          { "field": "state", "operator": "=", "value": "open" },
          { "field": "state", "operator": "=", "value": "snoozed" }
        ]
      },
      {
        "operator": "OR",
        "value": [
          { "field": "priority", "operator": "=", "value": "priority" },
          { "field": "admin_assignee_id", "operator": "=", "value": "12345" }
        ]
      }
    ]
  }
}
```

**Limits:** Max 2 nesting levels, max 15 filters per AND/OR group.

## Operators

| Operator | Valid Types | Description |
|----------|-------------|-------------|
| `=` | All | Equals |
| `!=` | All | Not equals |
| `IN` | All | In list (value must be array) |
| `NIN` | All | Not in list (value must be array) |
| `>` | Integer, Date (UNIX timestamp) | Greater than or equal |
| `<` | Integer, Date (UNIX timestamp) | Less than or equal |
| `~` | String | Contains |
| `!~` | String | Does not contain |
| `^` | String | Starts with |
| `$` | String | Ends with |

## Pagination (Cursor-Based)

Response includes a `pages` object:

```json
{
  "pages": {
    "type": "pages",
    "page": 1,
    "per_page": 25,
    "total_pages": 13,
    "next": {
      "per_page": 25,
      "starting_after": "WzE2OTk0OTMwNjYsMTM1LDJd"
    }
  }
}
```

To get the next page, pass `pages.next.starting_after` in the next request.
When `pages.next` is absent, there are no more pages.

---

## Conversation Searchable Fields

Endpoint: `POST /conversations/search`
Default per_page: 20, Max: 150

| Field | Type | Notes |
|-------|------|-------|
| `id` | String | |
| `created_at` | Date (UNIX ts) | |
| `updated_at` | Date (UNIX ts) | |
| `source.type` | String | `conversation`, `email`, `facebook`, `instagram`, `phone_call`, `phone_switch`, `push`, `sms`, `twitter`, `whatsapp` |
| `source.id` | String | |
| `source.delivered_as` | String | |
| `source.subject` | String | |
| `source.body` | String | Searched per-word, NOT substring. Search `"billing"` not `"billing issue"` |
| `source.author.id` | String | |
| `source.author.type` | String | |
| `source.author.name` | String | |
| `source.author.email` | String | |
| `source.url` | String | |
| `contact_ids` | String | |
| `teammate_ids` | String | |
| `admin_assignee_id` | String | `"0"` for unassigned |
| `team_assignee_id` | String | `"0"` for unassigned |
| `channel_initiated` | String | |
| `open` | Boolean | |
| `read` | Boolean | |
| `state` | String | `open`, `closed`, `snoozed` |
| `waiting_since` | Date (UNIX ts) | |
| `snoozed_until` | Date (UNIX ts) | |
| `tag_ids` | String | |
| `priority` | String | `priority`, `not_priority` |
| `statistics.time_to_assignment` | Integer | |
| `statistics.time_to_admin_reply` | Integer | |
| `statistics.time_to_first_close` | Integer | |
| `statistics.time_to_last_close` | Integer | |
| `statistics.median_time_to_reply` | Integer | |
| `statistics.first_contact_reply_at` | Date (UNIX ts) | |
| `statistics.first_assignment_at` | Date (UNIX ts) | |
| `statistics.first_admin_reply_at` | Date (UNIX ts) | |
| `statistics.first_close_at` | Date (UNIX ts) | |
| `statistics.last_assignment_at` | Date (UNIX ts) | |
| `statistics.last_assignment_admin_reply_at` | Date (UNIX ts) | |
| `statistics.last_contact_reply_at` | Date (UNIX ts) | |
| `statistics.last_admin_reply_at` | Date (UNIX ts) | |
| `statistics.last_close_at` | Date (UNIX ts) | |
| `statistics.last_closed_by_id` | String | |
| `statistics.count_reopens` | Integer | |
| `statistics.count_assignments` | Integer | |
| `statistics.count_conversation_parts` | Integer | |
| `conversation_rating.requested_at` | Date (UNIX ts) | |
| `conversation_rating.replied_at` | Date (UNIX ts) | |
| `conversation_rating.score` | Integer | |
| `conversation_rating.remark` | String | |
| `conversation_rating.contact_id` | String | |
| `conversation_rating.admin_d` | String | |
| `ai_agent_participated` | Boolean | |
| `ai_agent.resolution_state` | String | |
| `ai_agent.last_answer_type` | String | |
| `ai_agent.rating` | Integer | |
| `ai_agent.rating_remark` | String | |
| `ai_agent.source_type` | String | |
| `ai_agent.source_title` | String | |

---

## Contact Searchable Fields

Endpoint: `POST /contacts/search`
Default per_page: 50

| Field | Type | Notes |
|-------|------|-------|
| `id` | String | |
| `role` | String | `user` or `lead` |
| `name` | String | |
| `avatar` | String | |
| `owner_id` | Integer | |
| `email` | String | |
| `email_domain` | String | |
| `phone` | String | |
| `external_id` | String | |
| `created_at` | Date (UNIX ts) | Day granularity only |
| `signed_up_at` | Date (UNIX ts) | |
| `updated_at` | Date (UNIX ts) | |
| `last_seen_at` | Date (UNIX ts) | |
| `last_contacted_at` | Date (UNIX ts) | |
| `last_replied_at` | Date (UNIX ts) | |
| `last_email_opened_at` | Date (UNIX ts) | |
| `last_email_clicked_at` | Date (UNIX ts) | |
| `language_override` | String | |
| `browser` | String | |
| `browser_language` | String | |
| `os` | String | |
| `location.country` | String | |
| `location.region` | String | |
| `location.city` | String | |
| `unsubscribed_from_emails` | Boolean | |
| `marked_email_as_spam` | Boolean | |
| `has_hard_bounced` | Boolean | |
| `ios_last_seen_at` | Date (UNIX ts) | |
| `ios_app_version` | String | |
| `ios_device` | String | |
| `ios_app_device` | String | |
| `ios_os_version` | String | |
| `ios_app_name` | String | |
| `ios_sdk_version` | String | |
| `android_last_seen_at` | Date (UNIX ts) | |
| `android_app_version` | String | |
| `android_device` | String | |
| `android_app_name` | String | |
| `andoid_sdk_version` | String | Note: typo in official Intercom API spec |
| `segment_id` | String | |
| `tag_id` | String | |
| `custom_attributes.{name}` | String | Replace `{name}` with attribute name |

---

## Ticket Searchable Fields

Endpoint: `POST /tickets/search`
Default per_page: 20

| Field | Type | Notes |
|-------|------|-------|
| `id` | String | |
| `created_at` | Date (UNIX ts) | Supports `>=` and `<=` unlike contacts |
| `updated_at` | Date (UNIX ts) | |
| `title` | String | |
| `description` | String | |
| `category` | String | |
| `ticket_type_id` | String | |
| `contact_ids` | String | |
| `teammate_ids` | String | |
| `admin_assignee_id` | String | |
| `team_assignee_id` | String | |
| `open` | Boolean | |
| `state` | String | |
| `snoozed_until` | Date (UNIX ts) | |
| `ticket_attribute.{id}` | Varies | String, Boolean, Date, Float, or Integer |

---

## GET /conversations/{id}

Retrieves a single conversation with all message parts.

Query parameter: `display_as=plaintext` to strip HTML from message bodies.

Response includes `conversation_parts` array with up to 500 most recent parts.
Each part has: `type`, `id`, `part_type`, `body`, `created_at`, `author`, `attachments`.

Part types include: `comment`, `note`, `assignment`, `close`, `open`, `snoozed`, `unsnoozed`.

## GET /tags

Returns all tags in the workspace. No pagination, no request body.

Response:
```json
{
  "type": "list",
  "data": [
    { "type": "tag", "id": "115", "name": "Manual tag 1" }
  ]
}
```
