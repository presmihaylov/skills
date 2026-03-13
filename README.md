# Skills

Custom and forked skills for [Nairi](https://nairi.ai) agents.

## Skills

| Skill | Description | Source |
|-------|-------------|--------|
| [attio-crm](skills/attio-crm/) | Attio CRM operations for companies, contacts, deals, and notes | Fork of [casper-studios/casper-marketplace](https://github.com/casper-studios/casper-marketplace) |
| [bigquery](skills/bigquery/) | Query and explore Google BigQuery via REST API — zero SDK dependencies, base64-encoded service account key | Custom |
| [intercom](skills/intercom/) | Intercom API - conversation search, contact lookup, ticket search, tags | Custom |
| [plain-support](skills/plain-support/) | Plain customer support platform - customers, threads, timeline, help center (read-mostly) | Fork of [team-plain/skills](https://github.com/team-plain/skills) |
| [plain-support-rw](skills/plain-support-rw/) | Plain customer support platform - full read-write access for workspace setup and management | Fork of plain-support with all mutations |

## Usage

These skills are designed for use with Nairi agents via the [skills marketplace](https://nairi.ai). Each skill directory contains:

- `SKILL.md` - Skill definition with metadata and usage instructions
- `scripts/` - Executable scripts the agent uses
- `references/` - API docs and integration guides

## Changes from upstream

### attio-crm
- Added `get-company-summary` compound command - fetches company details, deals, notes, and tasks in a single invocation (reduces agent turns from 5+ to 1)
- Added `get-deal` and `search-deals` commands
- Added `--parent-object` flag to `list-notes` for deal notes support

### plain-support
- Added `format_response()` for clear JSON output on empty results instead of silent empty output
- Improved error feedback for customer search/get, thread search/list, company list, tenant list

### plain-support-rw
- Fork of plain-support with full CRUD mutations added for all resources
- **Customers**: upsert, delete, set-company
- **Threads**: create, reply, send-chat, send-email, note, delete-note, mark-done/todo, snooze, set-priority, assign/unassign, set-title, add/remove-labels, delete
- **Companies**: upsert, delete
- **Tenants**: upsert, delete, add/remove-customer
- **Labels**: create, update, archive/unarchive
- **Tiers**: create, update, delete, add/remove-members
- **Customer Groups**: create, list
- **Customer Events**: create (custom timeline entries)
- **Help Center**: create/update help centers, article upsert/delete, group create/update/delete
- Designed for sales engineers setting up demo workspaces
