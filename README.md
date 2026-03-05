# Skills

Custom and forked skills for [Nairi](https://nairi.ai) agents.

## Skills

| Skill | Description | Source |
|-------|-------------|--------|
| [attio-crm](skills/attio-crm/) | Attio CRM operations for companies, contacts, deals, and notes | Fork of [casper-studios/casper-marketplace](https://github.com/casper-studios/casper-marketplace) |
| [plain-support](skills/plain-support/) | Plain customer support platform - customers, threads, timeline, help center | Fork of [team-plain/skills](https://github.com/team-plain/skills) |

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
