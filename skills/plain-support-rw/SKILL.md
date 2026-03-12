---
name: plain-support-rw
description: Full read-write access to Plain customer support platform. Create and manage customers, threads, companies, tenants, labels, tiers, help center articles, and more. Designed for workspace setup and demo preparation.
license: MIT
compatibility: Requires curl, jq, and PLAIN_API_KEY environment variable
metadata:
  author: nairi
  version: "1.0"
allowed-tools: Bash Read
---

# Plain API Skill (Read-Write)

Full read-write access to the Plain customer support platform via GraphQL API. This skill enables complete workspace management: create customers, support threads, companies, tenants, labels, tiers, customer groups, and help center content.

**Use case:** Sales engineers setting up Plain workspaces for demos, or ops teams managing workspace configuration programmatically.

## Prerequisites

- `PLAIN_API_KEY` environment variable set with your API key
- `curl` and `jq` installed

## Quick Reference

### Customers (Read + Write)

```bash
# List customers
scripts/plain-api.sh customer list --first 10

# Get customer by ID / email / external ID
scripts/plain-api.sh customer get c_01ABC...
scripts/plain-api.sh customer get-by-email user@example.com
scripts/plain-api.sh customer get-by-external-id your-system-id

# Search customers
scripts/plain-api.sh customer search "john doe"

# Create or update customer
scripts/plain-api.sh customer upsert --email user@example.com --name "John Doe"
scripts/plain-api.sh customer upsert --email user@example.com --name "John Doe" --external-id usr-123

# Delete customer
scripts/plain-api.sh customer delete c_01ABC...

# Set customer's company
scripts/plain-api.sh customer set-company --customer c_01ABC... --company co_01ABC...
```

### Threads (Read + Write)

```bash
# List threads (TODO status by default)
scripts/plain-api.sh thread list --first 20

# List all threads or filter by status/priority
scripts/plain-api.sh thread list --status all
scripts/plain-api.sh thread list --status DONE
scripts/plain-api.sh thread list --priority urgent
scripts/plain-api.sh thread list --status TODO --priority high

# Get thread details
scripts/plain-api.sh thread get th_01ABC...

# Search threads
scripts/plain-api.sh thread search "billing issue"

# Get thread timeline (messages, events, status changes)
scripts/plain-api.sh thread timeline th_01ABC... --first 50

# Create a new thread
scripts/plain-api.sh thread create --customer-email user@example.com --title "Bug Report" --text "App crashes on login"
scripts/plain-api.sh thread create --customer-id c_01ABC... --title "Feature Request" --text "Details..." --priority high
scripts/plain-api.sh thread create --customer-email user@example.com --title "Issue" --text "..." --labels lt_01...,lt_02...

# Reply to thread (visible to customer)
scripts/plain-api.sh thread reply th_01ABC... --text "We're looking into this"

# Send chat message in thread
scripts/plain-api.sh thread send-chat th_01ABC... --text "Quick update: fix deployed"

# Send email to customer (creates new thread)
scripts/plain-api.sh thread send-email --customer c_01ABC... --subject "Welcome!" --text "Thanks for signing up"

# Add internal note (not visible to customer)
scripts/plain-api.sh thread note th_01ABC... --text "Escalated to engineering"
scripts/plain-api.sh thread note th_01ABC... --text "Note text" --markdown "**Bold** note"
scripts/plain-api.sh thread note th_01ABC... --text-file /path/to/note.txt

# Delete a note
scripts/plain-api.sh thread delete-note n_01ABC...

# Change thread status
scripts/plain-api.sh thread mark-done th_01ABC...
scripts/plain-api.sh thread mark-todo th_01ABC...
scripts/plain-api.sh thread snooze th_01ABC... --duration 7200

# Change priority
scripts/plain-api.sh thread set-priority th_01ABC... --priority urgent

# Update title
scripts/plain-api.sh thread set-title th_01ABC... --title "Updated Title"

# Assign/unassign thread
scripts/plain-api.sh thread assign th_01ABC...
scripts/plain-api.sh thread assign th_01ABC... --user u_01ABC...
scripts/plain-api.sh thread unassign th_01ABC...

# Add/remove labels
scripts/plain-api.sh thread add-labels th_01ABC... --labels lt_01...,lt_02...
scripts/plain-api.sh thread remove-labels --label-ids l_01...,l_02...

# Delete thread
scripts/plain-api.sh thread delete th_01ABC...
```

**Thread list options:**
| Option | Description |
|--------|-------------|
| `--status` | Filter by status: `TODO`, `SNOOZED`, `DONE`, or `all` |
| `--priority` | Filter by priority: `urgent`, `high`, `normal`, `low` |
| `--customer` | Filter by customer ID |
| `--first` | Number of results (default: 10) |

### Companies (Read + Write)

```bash
# List companies
scripts/plain-api.sh company list --first 10

# Get company by ID
scripts/plain-api.sh company get co_01ABC...

# Create or update company
scripts/plain-api.sh company upsert --name "Acme Inc" --domain acme.com
scripts/plain-api.sh company upsert --id co_01ABC... --name "Updated Acme" --domain acme.com

# Delete company
scripts/plain-api.sh company delete co_01ABC...
```

### Tenants (Read + Write)

```bash
# List tenants
scripts/plain-api.sh tenant list --first 10

# Get tenant by ID
scripts/plain-api.sh tenant get te_01ABC...

# Create or update tenant
scripts/plain-api.sh tenant upsert --external-id tenant-acme --name "Acme Corp"

# Delete tenant
scripts/plain-api.sh tenant delete tenant-acme

# Add customer to tenants
scripts/plain-api.sh tenant add-customer --customer c_01ABC... --tenants tenant-acme,tenant-other

# Remove customer from tenants
scripts/plain-api.sh tenant remove-customer --customer c_01ABC... --tenants tenant-acme
```

### Labels (Read + Write)

```bash
# List label types
scripts/plain-api.sh label list --first 20

# Create label type
scripts/plain-api.sh label create --name "bug"

# Update label type name
scripts/plain-api.sh label update lt_01ABC... --name "critical-bug"

# Archive/unarchive label type
scripts/plain-api.sh label archive lt_01ABC...
scripts/plain-api.sh label unarchive lt_01ABC...
```

### Tiers (Read + Write)

```bash
# List tiers
scripts/plain-api.sh tier list

# Get tier details
scripts/plain-api.sh tier get tier_01ABC...

# Create tier
scripts/plain-api.sh tier create --name "Enterprise" --external-id tier-enterprise --color "#3B82F6"

# Update tier
scripts/plain-api.sh tier update tier_01ABC... --name "Premium" --color "#10B981"

# Delete tier
scripts/plain-api.sh tier delete tier_01ABC...

# Add/remove members (tenants) to tier
scripts/plain-api.sh tier add-members --tier tier-enterprise --tenant-ids te_01...,te_02...
scripts/plain-api.sh tier remove-members --tier tier-enterprise --tenant-ids te_01...
```

### Customer Groups (Read + Write)

```bash
# List customer groups
scripts/plain-api.sh customer-group list

# Create customer group
scripts/plain-api.sh customer-group create --name "VIP Customers" --key "vip" --color "#EF4444"
```

### Customer Events (Write)

```bash
# Create a custom timeline entry for a customer
scripts/plain-api.sh customer-event create --customer c_01ABC... --title "Signed up for trial" --text "User started a 14-day trial"
```

### Help Center (Read + Write)

```bash
# List help centers
scripts/plain-api.sh helpcenter list

# Get help center details
scripts/plain-api.sh helpcenter get hc_01ABC...

# Create help center
scripts/plain-api.sh helpcenter create --public-name "Help Center" --internal-name "main-help" \
  --description "Customer documentation" --subdomain help --type SELF_SERVICE

# Update help center
scripts/plain-api.sh helpcenter update hc_01ABC... --public-name "Updated Help Center"

# List articles in help center
scripts/plain-api.sh helpcenter articles hc_01ABC... --first 20

# Get article by ID or slug
scripts/plain-api.sh helpcenter article get hca_01ABC...
scripts/plain-api.sh helpcenter article get-by-slug hc_01ABC... my-article-slug

# Create article (defaults to DRAFT)
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "Getting Started" \
  --description "Quick start guide" \
  --content "<h1>Welcome</h1><p>Follow these steps...</p>"

# Create and publish article
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "FAQ" \
  --description "Frequently asked questions" \
  --content "<p>Common questions</p>" \
  --status PUBLISHED

# Update existing article
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --id hca_01ABC... \
  --title "Updated Title" \
  --description "Updated description" \
  --content "<p>New content</p>"

# Use --content-file for large HTML content
scripts/plain-api.sh helpcenter article upsert hc_01ABC... \
  --title "Detailed Guide" \
  --description "Full documentation" \
  --content-file /path/to/article.html \
  --status PUBLISHED

# Delete article
scripts/plain-api.sh helpcenter article delete hca_01ABC...

# Manage article groups
scripts/plain-api.sh helpcenter group get hcag_01ABC...
scripts/plain-api.sh helpcenter group create hc_01ABC... --name "Getting Started"
scripts/plain-api.sh helpcenter group create hc_01ABC... --name "Advanced" --parent hcag_01PARENT...
scripts/plain-api.sh helpcenter group update hcag_01ABC... --name "New Group Name"
scripts/plain-api.sh helpcenter group delete hcag_01ABC...
```

### Workspace

```bash
# Get current workspace info
scripts/plain-api.sh workspace
```

## Common Workflows

### Set up a demo workspace from scratch

1. Create label types: `label create --name "bug"`, `label create --name "feature-request"`, etc.
2. Create tiers: `tier create --name "Free" --external-id free --color "#6B7280"`, etc.
3. Create tenants: `tenant upsert --external-id acme --name "Acme Corp"`
4. Create customers: `customer upsert --email alice@acme.com --name "Alice Smith"`
5. Add customers to tenants: `tenant add-customer --customer c_... --tenants acme`
6. Create threads: `thread create --customer-email alice@acme.com --title "Login issue" --text "Can't log in" --labels lt_..., --priority high`
7. Add notes/replies: `thread note th_... --text "Investigating"`, `thread reply th_... --text "Fixed!"`
8. Create help center content: `helpcenter create ...`, `helpcenter article upsert ...`

### Manage thread lifecycle

1. Create: `thread create --customer-email ... --title "..." --text "..."`
2. Triage: `thread set-priority th_... --priority high`, `thread add-labels th_... --labels lt_bug`
3. Assign: `thread assign th_... --user u_...`
4. Respond: `thread reply th_... --text "..."` or `thread send-chat th_... --text "..."`
5. Note: `thread note th_... --text "Internal context"`
6. Resolve: `thread mark-done th_...`

### Bulk customer setup

1. Create company: `company upsert --name "Acme" --domain acme.com`
2. Create tenant: `tenant upsert --external-id acme --name "Acme Corp"`
3. Create customers: loop `customer upsert --email ... --name ...`
4. Associate: `tenant add-customer --customer c_... --tenants acme`
5. Set company: `customer set-company --customer c_... --company co_...`

## Entity Reference

See [references/ENTITIES.md](references/ENTITIES.md) for detailed documentation on all entities including:

- Customer fields and statuses
- Thread status, priority, and channels
- Timeline entry types
- Company and Tenant structures
- Label and LabelType definitions
- Help Center, Article, and ArticleGroup schemas
- Tier and SLA configurations
- Customer Group definitions

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PLAIN_API_KEY` | Yes | Your Plain API key |
| `PLAIN_API_URL` | No | API endpoint (default: `https://core-api.uk.plain.com/graphql/v1`) |

## Output Format

All commands return JSON. Use `jq` for parsing:

```bash
# Get customer ID from upsert
scripts/plain-api.sh customer upsert --email user@example.com --name "Test" | jq -r '.data.upsertCustomer.customer.id'

# Get thread IDs
scripts/plain-api.sh thread list | jq '.data.threads.edges[].node.id'

# Get link from article creation
scripts/plain-api.sh helpcenter article upsert hc_... --title "Test" --description "Test" --content "<p>Test</p>" | jq -r '.link'
```
