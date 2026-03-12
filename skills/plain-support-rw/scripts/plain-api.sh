#!/bin/bash
# Plain API CLI - Full read-write access to Plain customer support platform
# Requires: PLAIN_API_KEY environment variable, curl, jq

set -euo pipefail

API_URL="${PLAIN_API_URL:-https://core-api.uk.plain.com/graphql/v1}"

# Check required dependencies
check_deps() {
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
    [ -n "${PLAIN_API_KEY:-}" ] || { echo "Error: PLAIN_API_KEY environment variable is required" >&2; exit 1; }
}

# Execute GraphQL query
gql() {
    local query="$1"
    local empty_json='{}'
    local variables="${2:-$empty_json}"

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

# Format and validate GraphQL response
format_response() {
    local response="$1"
    local resource_type="${2:-results}"

    local errors
    errors=$(echo "$response" | jq -r '.errors // empty')
    if [[ -n "$errors" ]] && [[ "$errors" != "null" ]]; then
        echo "$response" | jq '{errors: .errors}' >&2
        return 1
    fi

    local has_data
    has_data=$(echo "$response" | jq '
        .data // null |
        if . == null then false
        elif type == "object" then
            to_entries | map(.value) | map(
                if . == null then false
                elif type == "object" and has("edges") then (.edges | length > 0)
                elif type == "object" then true
                else . != null
                end
            ) | any
        else . != null
        end
    ')

    if [[ "$has_data" == "false" ]]; then
        echo "{\"message\": \"No $resource_type found\", \"data\": null}"
        return 0
    fi

    echo "$response"
}

# Convert priority label to number for API
priority_to_number() {
    case "$1" in
        urgent) echo 0 ;;
        high) echo 1 ;;
        normal) echo 2 ;;
        low) echo 3 ;;
        0|1|2|3) echo "$1" ;;
        *) echo "Error: Invalid priority '$1'. Use: urgent, high, normal, low" >&2; exit 1 ;;
    esac
}

# Map numeric priority values to labels in JSON output
map_priorities() {
    jq '
def priority_label:
  if . == 0 then "urgent"
  elif . == 1 then "high"
  elif . == 2 then "normal"
  elif . == 3 then "low"
  else .
  end;
walk(if type == "object" then
  (if has("priority") and (.priority | type) == "number" then .priority |= priority_label else . end) |
  (if has("previousPriority") and (.previousPriority | type) == "number" then .previousPriority |= priority_label else . end) |
  (if has("nextPriority") and (.nextPriority | type) == "number" then .nextPriority |= priority_label else . end)
else . end)'
}

# ============================================================================
# CUSTOMERS
# ============================================================================

customer_get() {
    local id="$1"
    local result
    result=$(gql 'query($id: ID!) { customer(customerId: $id) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}")
    format_response "$result" "customer"
}

customer_get_by_email() {
    local email="$1"
    local result
    result=$(gql 'query($email: String!) { customerByEmail(email: $email) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"email\": \"$email\"}")
    format_response "$result" "customer with email '$email'"
}

customer_get_by_external_id() {
    local external_id="$1"
    gql 'query($externalId: ID!) { customerByExternalId(externalId: $externalId) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"externalId\": \"$external_id\"}"
}

customer_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { customers(first: \$first) { edges { node { id fullName email { email } externalId status company { id name } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first}"
}

customer_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local result
    result=$(gql 'query($term: String!, $first: Int!) { searchCustomers(searchQuery: {or: [{fullName: {caseInsensitiveContains: $term}}, {email: {caseInsensitiveContains: $term}}]}, first: $first) { edges { node { id fullName email { email } externalId status company { id name } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}")
    format_response "$result" "customers matching '$query'"
}

customer_upsert() {
    local email=""
    local external_id=""
    local full_name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --email) email="$2"; shift 2 ;;
            --external-id) external_id="$2"; shift 2 ;;
            --name) full_name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$email" ]] || [[ -z "$full_name" ]]; then
        echo "Error: --email and --name are required" >&2
        echo "Usage: plain-api.sh customer upsert --email user@example.com --name \"John Doe\"" >&2
        exit 1
    fi

    local input
    input=$(jq -n \
        --arg email "$email" \
        --arg fullName "$full_name" \
        '{
            identifier: { emailAddress: $email },
            onCreate: { fullName: $fullName, email: { email: $email, isVerified: true } },
            onUpdate: { fullName: { value: $fullName } }
        }')

    if [[ -n "$external_id" ]]; then
        input=$(echo "$input" | jq --arg eid "$external_id" '
            .onCreate.externalId = $eid |
            .onUpdate.externalId = { value: $eid }')
    fi

    local query='mutation($input: UpsertCustomerInput!) { upsertCustomer(input: $input) { customer { id fullName email { email isVerified } externalId status } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

customer_delete() {
    local id="$1"
    gql 'mutation($input: DeleteCustomerInput!) { deleteCustomer(input: $input) { error { message code } } }' \
        "{\"input\": {\"customerId\": \"$id\"}}"
}

customer_set_company() {
    local customer_id=""
    local company_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --company) company_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$customer_id" ]]; then
        echo "Error: --customer is required" >&2
        exit 1
    fi

    local input
    if [[ -n "$company_id" ]]; then
        input=$(jq -n --arg cid "$customer_id" --arg coId "$company_id" \
            '{customerId: $cid, companyIdentifier: {companyId: $coId}}')
    else
        # Remove from company
        input=$(jq -n --arg cid "$customer_id" '{customerId: $cid}')
    fi

    gql 'mutation($input: UpdateCustomerCompanyInput!) { updateCustomerCompany(input: $input) { customer { id fullName company { id name } } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

# ============================================================================
# THREADS
# ============================================================================

thread_get() {
    local id="$1"
    gql 'query($id: ID!) { thread(threadId: $id) { id title description previewText status priority externalId channel customer { id fullName email { email } } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } labels { id labelType { id name } } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}" | map_priorities
}

thread_list() {
    local first=10
    local status_filter=""
    local priority_filter=""
    local customer_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --status)
                if [[ "$2" != "all" ]]; then
                    status_filter="$2"
                fi
                shift 2 ;;
            --priority) priority_filter="$(priority_to_number "$2")"; shift 2 ;;
            --customer) customer_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filter_parts=()
    if [[ -n "$status_filter" ]]; then
        filter_parts+=("\"statuses\": [\"$status_filter\"]")
    fi
    if [[ -n "$priority_filter" ]]; then
        filter_parts+=("\"priorities\": [$priority_filter]")
    fi
    if [[ -n "$customer_filter" ]]; then
        filter_parts+=("\"customerIds\": [\"$customer_filter\"]")
    fi

    local filter="{}"
    if [[ ${#filter_parts[@]} -gt 0 ]]; then
        filter="{$(IFS=,; echo "${filter_parts[*]}")}"
    fi

    local result
    result=$(gql "query(\$first: Int!, \$filters: ThreadsFilter) { threads(first: \$first, filters: \$filters) { edges { node { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } createdAt { iso8601 } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first, \"filters\": $filter}")
    format_response "$result" "threads" | map_priorities
}

thread_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local result
    result=$(gql 'query($term: String!, $first: Int!) { searchThreads(searchQuery: {term: $term}, first: $first) { edges { node { thread { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } } createdAt { iso8601 } } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}")
    format_response "$result" "threads matching '$query'" | map_priorities
}

thread_timeline() {
    local thread_id=""
    local first=20
    local after=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --after) after="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        exit 1
    fi

    local after_param=""
    if [[ -n "$after" ]]; then
        after_param=", \"after\": \"$after\""
    fi

    local query='query($threadId: ID!, $first: Int!, $after: String) {
      thread(threadId: $threadId) {
        timelineEntries(first: $first, after: $after) {
          edges {
            cursor
            node {
              id
              timestamp { iso8601 }
              actor {
                __typename
                ... on UserActor { userId }
                ... on SystemActor { systemId }
                ... on MachineUserActor { machineUserId machineUser { id fullName } }
                ... on CustomerActor { customerId customer { id fullName email { email } } }
                ... on DeletedCustomerActor { customerId }
              }
              entry {
                __typename
                ... on NoteEntry { noteId text markdown }
                ... on ChatEntry { chatId chatText: text }
                ... on EmailEntry { emailId subject textContent from { name email } to { name email } sentAt { iso8601 } }
                ... on CustomEntry { externalId title type }
                ... on SlackMessageEntry { text slackMessageLink }
                ... on SlackReplyEntry { text slackMessageLink }
                ... on ThreadStatusTransitionedEntry { nextStatus }
                ... on ThreadPriorityChangedEntry { previousPriority nextPriority }
                ... on ThreadAssignmentTransitionedEntry { previousAssignee { __typename ... on User { id fullName } ... on MachineUser { id fullName } } nextAssignee { __typename ... on User { id fullName } ... on MachineUser { id fullName } } }
                ... on ThreadLabelsChangedEntry { previousLabels { id labelType { id name } } nextLabels { id labelType { id name } } }
              }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }'

    gql "$query" "{\"threadId\": \"$thread_id\", \"first\": $first$after_param}" | map_priorities
}

thread_create() {
    local customer_email=""
    local customer_id=""
    local title=""
    local text=""
    local text_file=""
    local label_type_ids=""
    local priority=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer-email) customer_email="$2"; shift 2 ;;
            --customer-id) customer_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            --labels) label_type_ids="$2"; shift 2 ;;
            --priority) priority="$(priority_to_number "$2")"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$text_file" ]]; then
        [[ -f "$text_file" ]] || { echo "Error: Text file not found: $text_file" >&2; exit 1; }
        text=$(cat "$text_file")
    fi

    if [[ -z "$title" ]] || [[ -z "$text" ]]; then
        echo "Error: --title and --text (or --text-file) are required" >&2
        echo "Usage: plain-api.sh thread create --customer-email user@example.com --title \"Issue\" --text \"Description\"" >&2
        exit 1
    fi

    if [[ -z "$customer_email" ]] && [[ -z "$customer_id" ]]; then
        echo "Error: --customer-email or --customer-id is required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg title "$title" --arg text "$text" \
        '{title: $title, components: [{componentText: {text: $text}}]}')

    if [[ -n "$customer_email" ]]; then
        input=$(echo "$input" | jq --arg email "$customer_email" '.customerIdentifier = {emailAddress: $email}')
    else
        input=$(echo "$input" | jq --arg cid "$customer_id" '.customerIdentifier = {customerId: $cid}')
    fi

    if [[ -n "$label_type_ids" ]]; then
        input=$(echo "$input" | jq --arg ids "$label_type_ids" '.labelTypeIds = ($ids | split(","))')
    fi

    if [[ -n "$priority" ]]; then
        input=$(echo "$input" | jq --argjson p "$priority" '.priority = $p')
    fi

    local query='mutation($input: CreateThreadInput!) { createThread(input: $input) { thread { id title status priority customer { id fullName } } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')" | map_priorities
}

thread_reply() {
    local thread_id=""
    local text=""
    local text_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --text) text="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            '') shift ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -n "$text_file" ]]; then
        [[ -f "$text_file" ]] || { echo "Error: Text file not found: $text_file" >&2; exit 1; }
        text=$(cat "$text_file")
    fi

    if [[ -z "$thread_id" ]] || [[ -z "$text" ]]; then
        echo "Error: thread_id and --text (or --text-file) are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg tid "$thread_id" --arg text "$text" '{threadId: $tid, textContent: $text}')

    gql 'mutation($input: ReplyToThreadInput!) { replyToThread(input: $input) { error { message code fields { field message type } } } }' \
        "{\"input\": $(echo "$input")}"
}

thread_note() {
    local thread_id=""
    local text=""
    local markdown=""
    local text_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --text) text="$2"; shift 2 ;;
            --markdown) markdown="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            '') shift ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -n "$text_file" ]]; then
        [[ -f "$text_file" ]] || { echo "Error: Text file not found: $text_file" >&2; exit 1; }
        text=$(cat "$text_file")
    fi

    if [[ -z "$thread_id" ]] || [[ -z "$text" ]]; then
        echo "Error: thread_id and --text (or --text-file) are required" >&2
        exit 1
    fi

    # Get customer ID from thread
    local thread_result
    thread_result=$(gql 'query($id: ID!) { thread(threadId: $id) { id customer { id } } }' "{\"id\": \"$thread_id\"}")
    local customer_id
    customer_id=$(echo "$thread_result" | jq -r '.data.thread.customer.id // empty')
    if [[ -z "$customer_id" ]]; then
        echo "Error: Could not find thread $thread_id" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg cid "$customer_id" --arg tid "$thread_id" --arg text "$text" \
        '{customerId: $cid, threadId: $tid, text: $text}')

    if [[ -n "$markdown" ]]; then
        input=$(echo "$input" | jq --arg md "$markdown" '. + {markdown: $md}')
    fi

    local query='mutation($input: CreateNoteInput!) { createNote(input: $input) { note { id text } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

thread_delete_note() {
    local note_id="$1"
    gql 'mutation($input: DeleteNoteInput!) { deleteNote(input: $input) { error { message code } } }' \
        "{\"input\": {\"noteId\": \"$note_id\"}}"
}

thread_mark_done() {
    local thread_id="$1"
    gql 'mutation($input: MarkThreadAsDoneInput!) { markThreadAsDone(input: $input) { thread { id status } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\"}}"
}

thread_mark_todo() {
    local thread_id="$1"
    gql 'mutation($input: MarkThreadAsTodoInput!) { markThreadAsTodo(input: $input) { thread { id status } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\"}}"
}

thread_snooze() {
    local thread_id=""
    local duration=3600

    while [[ $# -gt 0 ]]; do
        case $1 in
            --duration) duration="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        exit 1
    fi

    gql 'mutation($input: SnoozeThreadInput!) { snoozeThread(input: $input) { thread { id status } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\", \"durationSeconds\": $duration}}"
}

thread_set_priority() {
    local thread_id=""
    local priority=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --priority) priority="$(priority_to_number "$2")"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]] || [[ -z "$priority" ]]; then
        echo "Error: thread_id and --priority are required" >&2
        exit 1
    fi

    gql 'mutation($input: ChangeThreadPriorityInput!) { changeThreadPriority(input: $input) { thread { id priority } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\", \"priority\": $priority}}" | map_priorities
}

thread_assign() {
    local thread_id=""
    local user_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --user) user_id="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        exit 1
    fi

    local input="{\"threadId\": \"$thread_id\""
    [[ -n "$user_id" ]] && input="$input, \"userId\": \"$user_id\""
    input="$input}"

    gql 'mutation($input: AssignThreadInput!) { assignThread(input: $input) { thread { id assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } } error { message code } } }' \
        "{\"input\": $input}"
}

thread_unassign() {
    local thread_id="$1"
    gql 'mutation($input: UnassignThreadInput!) { unassignThread(input: $input) { thread { id } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\"}}"
}

thread_set_title() {
    local thread_id=""
    local title=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --title) title="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]] || [[ -z "$title" ]]; then
        echo "Error: thread_id and --title are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg tid "$thread_id" --arg title "$title" '{threadId: $tid, title: $title}')

    gql 'mutation($input: UpdateThreadTitleInput!) { updateThreadTitle(input: $input) { thread { id title } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

thread_delete() {
    local thread_id="$1"
    gql 'mutation($input: DeleteThreadInput!) { deleteThread(input: $input) { error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\"}}"
}

thread_add_labels() {
    local thread_id=""
    local label_type_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --labels) label_type_ids="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]] || [[ -z "$label_type_ids" ]]; then
        echo "Error: thread_id and --labels are required" >&2
        echo "Usage: plain-api.sh thread add-labels th_... --labels lt_...,lt_..." >&2
        exit 1
    fi

    local ids_json
    ids_json=$(echo "$label_type_ids" | jq -R 'split(",")')

    gql 'mutation($input: AddLabelsInput!) { addLabels(input: $input) { labels { id labelType { id name } } error { message code } } }' \
        "{\"input\": {\"threadId\": \"$thread_id\", \"labelTypeIds\": $ids_json}}"
}

thread_remove_labels() {
    local label_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --label-ids) label_ids="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$label_ids" ]]; then
        echo "Error: --label-ids are required (comma-separated label instance IDs, not label type IDs)" >&2
        exit 1
    fi

    local ids_json
    ids_json=$(echo "$label_ids" | jq -R 'split(",")')

    gql 'mutation($input: RemoveLabelsInput!) { removeLabels(input: $input) { error { message code } } }' \
        "{\"input\": {\"labelIds\": $ids_json}}"
}

thread_send_chat() {
    local thread_id=""
    local customer_id=""
    local text=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]] || [[ -z "$text" ]]; then
        echo "Error: thread_id and --text are required" >&2
        exit 1
    fi

    # Auto-resolve customer ID if not provided
    if [[ -z "$customer_id" ]]; then
        local thread_result
        thread_result=$(gql 'query($id: ID!) { thread(threadId: $id) { customer { id } } }' "{\"id\": \"$thread_id\"}")
        customer_id=$(echo "$thread_result" | jq -r '.data.thread.customer.id // empty')
        if [[ -z "$customer_id" ]]; then
            echo "Error: Could not resolve customer for thread $thread_id" >&2
            exit 1
        fi
    fi

    local input
    input=$(jq -n --arg tid "$thread_id" --arg cid "$customer_id" --arg text "$text" \
        '{threadId: $tid, customerId: $cid, text: $text}')

    gql 'mutation($input: SendChatInput!) { sendChat(input: $input) { chat { id text } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

thread_send_email() {
    local customer_id=""
    local subject=""
    local text=""
    local text_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --subject) subject="$2"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$text_file" ]]; then
        [[ -f "$text_file" ]] || { echo "Error: Text file not found: $text_file" >&2; exit 1; }
        text=$(cat "$text_file")
    fi

    if [[ -z "$customer_id" ]] || [[ -z "$subject" ]] || [[ -z "$text" ]]; then
        echo "Error: --customer, --subject, and --text (or --text-file) are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg cid "$customer_id" --arg subj "$subject" --arg text "$text" \
        '{customerId: $cid, subject: $subj, textContent: $text}')

    gql 'mutation($input: SendNewEmailInput!) { sendNewEmail(input: $input) { email { id } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

# ============================================================================
# COMPANIES
# ============================================================================

company_get() {
    local id="$1"
    gql 'query($id: ID!) { company(companyId: $id) { id name domainName createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

company_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local result
    result=$(gql "query(\$first: Int!) { companies(first: \$first) { edges { node { id name domainName } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}")
    format_response "$result" "companies"
}

company_upsert() {
    local company_id=""
    local name=""
    local domain=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id) company_id="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            --domain) domain="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Error: --name is required" >&2
        echo "Usage: plain-api.sh company upsert --name \"Acme Inc\" --domain acme.com" >&2
        exit 1
    fi

    local input
    if [[ -n "$company_id" ]]; then
        input=$(jq -n --arg cid "$company_id" --arg name "$name" \
            '{identifier: {companyId: $cid}, name: $name}')
    else
        input=$(jq -n --arg name "$name" '{name: $name}')
        # Without an ID, we still need an identifier
        if [[ -n "$domain" ]]; then
            input=$(echo "$input" | jq --arg d "$domain" '.identifier = {domainName: $d} | .domainName = $d')
        else
            echo "Error: --domain or --id is required to identify the company" >&2
            exit 1
        fi
    fi

    if [[ -n "$domain" ]] && [[ -n "$company_id" ]]; then
        input=$(echo "$input" | jq --arg d "$domain" '.domainName = $d')
    fi

    local query='mutation($input: UpsertCompanyInput!) { upsertCompany(input: $input) { company { id name domainName } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

company_delete() {
    local company_id="$1"
    gql 'mutation($input: DeleteCompanyInput!) { deleteCompany(input: $input) { error { message code } } }' \
        "{\"input\": {\"companyIdentifier\": {\"companyId\": \"$company_id\"}}}"
}

# ============================================================================
# TENANTS
# ============================================================================

tenant_get() {
    local id="$1"
    gql 'query($id: ID!) { tenant(tenantId: $id) { id name externalId createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

tenant_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local result
    result=$(gql "query(\$first: Int!) { tenants(first: \$first) { edges { node { id name externalId } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}")
    format_response "$result" "tenants"
}

tenant_upsert() {
    local external_id=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --external-id) external_id="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$external_id" ]] || [[ -z "$name" ]]; then
        echo "Error: --external-id and --name are required" >&2
        echo "Usage: plain-api.sh tenant upsert --external-id tenant-123 --name \"Acme Corp\"" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg eid "$external_id" --arg name "$name" \
        '{identifier: {externalId: $eid}, name: $name, externalId: $eid}')

    local query='mutation($input: UpsertTenantInput!) { upsertTenant(input: $input) { tenant { id name externalId } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

tenant_delete() {
    local external_id="$1"
    gql 'mutation($input: DeleteTenantInput!) { deleteTenant(input: $input) { error { message code } } }' \
        "{\"input\": {\"tenantIdentifier\": {\"externalId\": \"$external_id\"}}}"
}

tenant_add_customer() {
    local customer_id=""
    local tenant_external_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --tenants) tenant_external_ids="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$customer_id" ]] || [[ -z "$tenant_external_ids" ]]; then
        echo "Error: --customer and --tenants (comma-separated external IDs) are required" >&2
        exit 1
    fi

    local identifiers
    identifiers=$(echo "$tenant_external_ids" | jq -R '[split(",")[] | {externalId: .}]')

    gql 'mutation($input: AddCustomerToTenantsInput!) { addCustomerToTenants(input: $input) { error { message code } } }' \
        "{\"input\": {\"customerIdentifier\": {\"customerId\": \"$customer_id\"}, \"tenantIdentifiers\": $identifiers}}"
}

tenant_remove_customer() {
    local customer_id=""
    local tenant_external_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --tenants) tenant_external_ids="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$customer_id" ]] || [[ -z "$tenant_external_ids" ]]; then
        echo "Error: --customer and --tenants (comma-separated external IDs) are required" >&2
        exit 1
    fi

    local identifiers
    identifiers=$(echo "$tenant_external_ids" | jq -R '[split(",")[] | {externalId: .}]')

    gql 'mutation($input: RemoveCustomerFromTenantsInput!) { removeCustomerFromTenants(input: $input) { error { message code } } }' \
        "{\"input\": {\"customerIdentifier\": {\"customerId\": \"$customer_id\"}, \"tenantIdentifiers\": $identifiers}}"
}

# ============================================================================
# LABELS
# ============================================================================

label_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { labelTypes(first: \$first) { edges { node { id name isArchived } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

label_create() {
    local name=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        echo "Error: --name is required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg name "$name" '{name: $name}')

    gql 'mutation($input: CreateLabelTypeInput!) { createLabelType(input: $input) { labelType { id name } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

label_update() {
    local label_type_id=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) label_type_id="$1"; shift ;;
        esac
    done

    if [[ -z "$label_type_id" ]] || [[ -z "$name" ]]; then
        echo "Error: label_type_id and --name are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg id "$label_type_id" --arg name "$name" '{labelTypeId: $id, name: {value: $name}}')

    gql 'mutation($input: UpdateLabelTypeInput!) { updateLabelType(input: $input) { labelType { id name } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

label_archive() {
    local label_type_id="$1"
    gql 'mutation($input: ArchiveLabelTypeInput!) { archiveLabelType(input: $input) { labelType { id name isArchived } error { message code } } }' \
        "{\"input\": {\"labelTypeId\": \"$label_type_id\"}}"
}

label_unarchive() {
    local label_type_id="$1"
    gql 'mutation($input: UnarchiveLabelTypeInput!) { unarchiveLabelType(input: $input) { labelType { id name isArchived } error { message code } } }' \
        "{\"input\": {\"labelTypeId\": \"$label_type_id\"}}"
}

# ============================================================================
# TIERS
# ============================================================================

tier_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { tiers(first: \$first) { edges { node { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly } } } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

tier_get() {
    local id="$1"
    gql 'query($id: ID!) { tier(tierId: $id) { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } } memberships(first: 50) { edges { node { ... on TenantTierMembership { id tenantId } ... on CompanyTierMembership { id companyId } } } totalCount } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

tier_create() {
    local name=""
    local external_id=""
    local color="#3B82F6"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --external-id) external_id="$2"; shift 2 ;;
            --color) color="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]] || [[ -z "$external_id" ]]; then
        echo "Error: --name and --external-id are required" >&2
        echo "Usage: plain-api.sh tier create --name \"Enterprise\" --external-id tier-enterprise --color \"#3B82F6\"" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg name "$name" --arg eid "$external_id" --arg color "$color" \
        '{name: $name, externalId: $eid, color: $color, memberIdentifiers: []}')

    local query='mutation($input: CreateTierInput!) { createTier(input: $input) { tier { id name externalId color } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

tier_update() {
    local tier_id=""
    local name=""
    local color=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --color) color="$2"; shift 2 ;;
            *) tier_id="$1"; shift ;;
        esac
    done

    if [[ -z "$tier_id" ]]; then
        echo "Error: tier_id is required" >&2
        exit 1
    fi

    local input="{\"tierId\": \"$tier_id\""
    [[ -n "$name" ]] && input="$input, \"name\": {\"value\": \"$name\"}"
    [[ -n "$color" ]] && input="$input, \"color\": {\"value\": \"$color\"}"
    input="$input}"

    gql 'mutation($input: UpdateTierInput!) { updateTier(input: $input) { tier { id name color } error { message code } } }' \
        "{\"input\": $input}"
}

tier_delete() {
    local tier_id="$1"
    gql 'mutation($input: DeleteTierInput!) { deleteTier(input: $input) { error { message code } } }' \
        "{\"input\": {\"tierId\": \"$tier_id\"}}"
}

tier_add_members() {
    local tier_external_id=""
    local tenant_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --tier) tier_external_id="$2"; shift 2 ;;
            --tenant-ids) tenant_ids="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$tier_external_id" ]] || [[ -z "$tenant_ids" ]]; then
        echo "Error: --tier (external ID) and --tenant-ids (comma-separated) are required" >&2
        exit 1
    fi

    local members
    members=$(echo "$tenant_ids" | jq -R '[split(",")[] | {tenantId: .}]')

    gql 'mutation($input: AddMembersToTierInput!) { addMembersToTier(input: $input) { error { message code } } }' \
        "{\"input\": {\"tierIdentifier\": {\"externalId\": \"$tier_external_id\"}, \"memberIdentifiers\": $members}}"
}

tier_remove_members() {
    local tier_external_id=""
    local tenant_ids=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --tier) tier_external_id="$2"; shift 2 ;;
            --tenant-ids) tenant_ids="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$tier_external_id" ]] || [[ -z "$tenant_ids" ]]; then
        echo "Error: --tier (external ID) and --tenant-ids (comma-separated) are required" >&2
        exit 1
    fi

    local members
    members=$(echo "$tenant_ids" | jq -R '[split(",")[] | {tenantId: .}]')

    gql 'mutation($input: RemoveMembersFromTierInput!) { removeMembersFromTier(input: $input) { error { message code } } }' \
        "{\"input\": {\"tierIdentifier\": {\"externalId\": \"$tier_external_id\"}, \"memberIdentifiers\": $members}}"
}

# ============================================================================
# CUSTOMER GROUPS
# ============================================================================

customer_group_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { customerGroups(first: \$first) { edges { node { id name key color } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

customer_group_create() {
    local name=""
    local key=""
    local color="#3B82F6"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --key) key="$2"; shift 2 ;;
            --color) color="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$name" ]] || [[ -z "$key" ]]; then
        echo "Error: --name and --key are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n --arg name "$name" --arg key "$key" --arg color "$color" \
        '{name: $name, key: $key, color: $color}')

    gql 'mutation($input: CreateCustomerGroupInput!) { createCustomerGroup(input: $input) { customerGroup { id name key color } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

# ============================================================================
# CUSTOMER EVENTS (Custom Timeline Entries)
# ============================================================================

customer_event_create() {
    local customer_id=""
    local title=""
    local text=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --text) text="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$customer_id" ]] || [[ -z "$title" ]]; then
        echo "Error: --customer and --title are required" >&2
        exit 1
    fi

    local components="[]"
    if [[ -n "$text" ]]; then
        components=$(jq -n --arg text "$text" '[{componentText: {text: $text}}]')
    fi

    local input
    input=$(jq -n --arg cid "$customer_id" --arg title "$title" --argjson comps "$components" \
        '{customerIdentifier: {customerId: $cid}, title: $title, components: $comps}')

    gql 'mutation($input: CreateCustomerEventInput!) { createCustomerEvent(input: $input) { customerEvent { id title } error { message code } } }' \
        "{\"input\": $(echo "$input")}"
}

# ============================================================================
# HELP CENTER
# ============================================================================

helpcenter_list() {
    gql '{ helpCenters(first: 50) { edges { node { id publicName internalName description type } } } }' '{}'
}

helpcenter_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenter(id: $id) { id publicName internalName description type articleGroups(first: 50) { edges { node { id name slug } } } articles(first: 50) { edges { node { id title slug status } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_create() {
    local public_name=""
    local internal_name=""
    local description=""
    local subdomain=""
    local type="SELF_SERVICE"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --public-name) public_name="$2"; shift 2 ;;
            --internal-name) internal_name="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --subdomain) subdomain="$2"; shift 2 ;;
            --type) type="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$public_name" ]] || [[ -z "$internal_name" ]] || [[ -z "$description" ]] || [[ -z "$subdomain" ]]; then
        echo "Error: --public-name, --internal-name, --description, and --subdomain are required" >&2
        exit 1
    fi

    local input
    input=$(jq -n \
        --arg pn "$public_name" --arg in_ "$internal_name" --arg desc "$description" \
        --arg sub "$subdomain" --arg type "$type" \
        '{publicName: $pn, internalName: $in_, description: $desc, subdomain: $sub, type: $type}')

    local query='mutation($input: CreateHelpCenterInput!) { createHelpCenter(input: $input) { helpCenter { id publicName internalName type } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

helpcenter_update() {
    local help_center_id=""
    local public_name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --public-name) public_name="$2"; shift 2 ;;
            *) help_center_id="$1"; shift ;;
        esac
    done

    if [[ -z "$help_center_id" ]]; then
        echo "Error: help_center_id is required" >&2
        exit 1
    fi

    local input="{\"helpCenterId\": \"$help_center_id\""
    [[ -n "$public_name" ]] && input="$input, \"publicName\": \"$public_name\""
    input="$input}"

    gql 'mutation($input: UpdateHelpCenterInput!) { updateHelpCenter(input: $input) { helpCenter { id publicName } error { message code } } }' \
        "{\"input\": $input}"
}

helpcenter_articles() {
    local help_center_id="$1"
    shift || true
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($id: ID!, $first: Int!) { helpCenter(id: $id) { articles(first: $first) { edges { node { id title slug status description contentHtml articleGroup { id name } } } pageInfo { hasNextPage endCursor } } } }' \
        "{\"id\": \"$help_center_id\", \"first\": $first}"
}

helpcenter_article_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticle(id: $id) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_article_get_by_slug() {
    local help_center_id="$1"
    local slug="$2"
    gql 'query($helpCenterId: ID!, $slug: String!) { helpCenterArticleBySlug(helpCenterId: $helpCenterId, slug: $slug) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"helpCenterId\": \"$help_center_id\", \"slug\": \"$slug\"}"
}

helpcenter_article_upsert() {
    local help_center_id=""
    local article_id=""
    local title=""
    local description=""
    local content=""
    local content_file=""
    local group_id=""
    local status="DRAFT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id) article_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --content-file) content_file="$2"; shift 2 ;;
            --group) group_id="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            '') shift ;;
            *) help_center_id="$1"; shift ;;
        esac
    done

    if [[ -n "$content_file" ]]; then
        [[ -f "$content_file" ]] || { echo "Error: Content file not found: $content_file" >&2; exit 1; }
        content=$(cat "$content_file")
    fi

    if [[ -z "$help_center_id" ]] || [[ -z "$title" ]] || [[ -z "$description" ]] || [[ -z "$content" ]]; then
        echo "Error: help_center_id, --title, --description, and --content (or --content-file) are required" >&2
        exit 1
    fi

    if [[ "$status" != "DRAFT" ]] && [[ "$status" != "PUBLISHED" ]]; then
        echo "Error: --status must be DRAFT or PUBLISHED" >&2
        exit 1
    fi

    local workspace_result
    workspace_result=$(gql '{ myWorkspace { id } }' '{}')
    local workspace_id
    workspace_id=$(echo "$workspace_result" | jq -r '.data.myWorkspace.id')

    local input
    input=$(jq -n \
        --arg helpCenterId "$help_center_id" \
        --arg title "$title" \
        --arg description "$description" \
        --arg contentHtml "$content" \
        --arg status "$status" \
        '{helpCenterId: $helpCenterId, title: $title, description: $description, contentHtml: $contentHtml, status: $status}')

    [[ -n "$article_id" ]] && input=$(echo "$input" | jq --arg id "$article_id" '. + {helpCenterArticleId: $id}')
    [[ -n "$group_id" ]] && input=$(echo "$input" | jq --arg id "$group_id" '. + {helpCenterArticleGroupId: $id}')

    local query='mutation($input: UpsertHelpCenterArticleInput!) { upsertHelpCenterArticle(input: $input) { helpCenterArticle { id title slug status } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    local result
    result=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')")

    local new_article_id
    new_article_id=$(echo "$result" | jq -r '.data.upsertHelpCenterArticle.helpCenterArticle.id // empty')

    if [[ -n "$new_article_id" ]]; then
        local link="https://app.plain.com/workspace/${workspace_id}/help-center/${help_center_id}/articles/${new_article_id}/"
        echo "$result" | jq --arg link "$link" '.link = $link'
    else
        echo "$result"
    fi
}

helpcenter_article_delete() {
    local article_id="$1"
    gql 'mutation($input: DeleteHelpCenterArticleInput!) { deleteHelpCenterArticle(input: $input) { error { message code } } }' \
        "{\"input\": {\"helpCenterArticleId\": \"$article_id\"}}"
}

helpcenter_group_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticleGroup(id: $id) { id name slug parentArticleGroup { id name } articles(first: 50) { edges { node { id title slug status } } } childArticleGroups(first: 50) { edges { node { id name slug } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_group_create() {
    local help_center_id=""
    local name=""
    local parent_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --parent) parent_id="$2"; shift 2 ;;
            *) help_center_id="$1"; shift ;;
        esac
    done

    if [[ -z "$help_center_id" ]] || [[ -z "$name" ]]; then
        echo "Error: help_center_id and --name are required" >&2
        exit 1
    fi

    local input="{\"helpCenterId\": \"$help_center_id\", \"name\": \"$name\""
    [[ -n "$parent_id" ]] && input="$input, \"parentHelpCenterArticleGroupId\": \"$parent_id\""
    input="$input}"

    gql 'mutation($input: CreateHelpCenterArticleGroupInput!) { createHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": $input}"
}

helpcenter_group_update() {
    local group_id=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) group_id="$1"; shift ;;
        esac
    done

    if [[ -z "$group_id" ]] || [[ -z "$name" ]]; then
        echo "Error: group_id and --name are required" >&2
        exit 1
    fi

    gql 'mutation($input: UpdateHelpCenterArticleGroupInput!) { updateHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$group_id\", \"name\": \"$name\"}}"
}

helpcenter_group_delete() {
    local id="$1"
    gql 'mutation($input: DeleteHelpCenterArticleGroupInput!) { deleteHelpCenterArticleGroup(input: $input) { error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$id\"}}"
}

# ============================================================================
# WORKSPACE
# ============================================================================

workspace_get() {
    gql '{ myWorkspace { id name publicName } }' '{}'
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat << 'EOF'
Plain API CLI (Read-Write) - Full access to Plain customer support platform

USAGE: plain-api.sh <resource> <action> [options]

RESOURCES:
  customer        Create, read, update, delete customers
  thread          Create, manage, reply to support threads
  company         Create, read, delete companies
  tenant          Create, read, delete tenants; manage customer membership
  label           Create, update, archive/unarchive label types
  tier            Create, read, update, delete tiers; manage members
  customer-group  Create and list customer groups
  customer-event  Create custom timeline entries
  helpcenter      Create/update help centers, articles, and groups
  workspace       Get workspace info

EXAMPLES:
  # Customer management
  plain-api.sh customer upsert --email user@example.com --name "John Doe"
  plain-api.sh customer list --first 10
  plain-api.sh customer delete c_01ABC...

  # Thread management
  plain-api.sh thread create --customer-email user@example.com --title "Bug Report" --text "Details..."
  plain-api.sh thread reply th_01ABC... --text "Working on it"
  plain-api.sh thread send-chat th_01ABC... --text "Chat message"
  plain-api.sh thread note th_01ABC... --text "Internal note"
  plain-api.sh thread set-priority th_01ABC... --priority urgent
  plain-api.sh thread mark-done th_01ABC...
  plain-api.sh thread add-labels th_01ABC... --labels lt_01...,lt_02...
  plain-api.sh thread assign th_01ABC...
  plain-api.sh thread delete th_01ABC...

  # Labels
  plain-api.sh label create --name "bug"
  plain-api.sh label update lt_01ABC... --name "critical-bug"
  plain-api.sh label archive lt_01ABC...

  # Companies and tenants
  plain-api.sh company upsert --name "Acme" --domain acme.com
  plain-api.sh tenant upsert --external-id tenant-123 --name "Acme Corp"
  plain-api.sh tenant add-customer --customer c_01... --tenants tenant-123

  # Tiers
  plain-api.sh tier create --name "Enterprise" --external-id tier-ent --color "#3B82F6"
  plain-api.sh tier add-members --tier tier-ent --tenant-ids te_01...

  # Help center
  plain-api.sh helpcenter create --public-name "Help" --internal-name "help" --description "Support docs" --subdomain help
  plain-api.sh helpcenter article upsert hc_01... --title "Guide" --description "How to" --content "<p>Steps</p>" --status PUBLISHED
  plain-api.sh helpcenter group create hc_01... --name "Getting Started"

ENVIRONMENT:
  PLAIN_API_KEY   Required. Your Plain API key.
  PLAIN_API_URL   Optional. API endpoint (default: https://core-api.uk.plain.com/graphql/v1)
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local resource="$1"

    if [[ "$resource" == "help" ]] || [[ "$resource" == "--help" ]] || [[ "$resource" == "-h" ]]; then
        usage
        exit 0
    fi

    check_deps
    shift

    case "$resource" in
        customer)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) customer_get "$@" ;;
                get-by-email) customer_get_by_email "$@" ;;
                get-by-external-id) customer_get_by_external_id "$@" ;;
                list) customer_list "$@" ;;
                search) customer_search "$@" ;;
                upsert) customer_upsert "$@" ;;
                delete) customer_delete "$@" ;;
                set-company) customer_set_company "$@" ;;
                *) echo "Unknown customer action: $action" >&2; exit 1 ;;
            esac
            ;;
        thread)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) thread_get "$@" ;;
                list) thread_list "$@" ;;
                search) thread_search "$@" ;;
                timeline) thread_timeline "$@" ;;
                create) thread_create "$@" ;;
                reply) thread_reply "$@" ;;
                note) thread_note "$@" ;;
                delete-note) thread_delete_note "$@" ;;
                send-chat) thread_send_chat "$@" ;;
                send-email) thread_send_email "$@" ;;
                mark-done) thread_mark_done "$@" ;;
                mark-todo) thread_mark_todo "$@" ;;
                snooze) thread_snooze "$@" ;;
                set-priority) thread_set_priority "$@" ;;
                assign) thread_assign "$@" ;;
                unassign) thread_unassign "$@" ;;
                set-title) thread_set_title "$@" ;;
                add-labels) thread_add_labels "$@" ;;
                remove-labels) thread_remove_labels "$@" ;;
                delete) thread_delete "$@" ;;
                *) echo "Unknown thread action: $action" >&2; exit 1 ;;
            esac
            ;;
        company)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) company_get "$@" ;;
                list) company_list "$@" ;;
                upsert) company_upsert "$@" ;;
                delete) company_delete "$@" ;;
                *) echo "Unknown company action: $action" >&2; exit 1 ;;
            esac
            ;;
        tenant)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) tenant_get "$@" ;;
                list) tenant_list "$@" ;;
                upsert) tenant_upsert "$@" ;;
                delete) tenant_delete "$@" ;;
                add-customer) tenant_add_customer "$@" ;;
                remove-customer) tenant_remove_customer "$@" ;;
                *) echo "Unknown tenant action: $action" >&2; exit 1 ;;
            esac
            ;;
        label)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) label_list "$@" ;;
                create) label_create "$@" ;;
                update) label_update "$@" ;;
                archive) label_archive "$@" ;;
                unarchive) label_unarchive "$@" ;;
                *) echo "Unknown label action: $action" >&2; exit 1 ;;
            esac
            ;;
        tier)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) tier_list "$@" ;;
                get) tier_get "$@" ;;
                create) tier_create "$@" ;;
                update) tier_update "$@" ;;
                delete) tier_delete "$@" ;;
                add-members) tier_add_members "$@" ;;
                remove-members) tier_remove_members "$@" ;;
                *) echo "Unknown tier action: $action" >&2; exit 1 ;;
            esac
            ;;
        customer-group)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) customer_group_list "$@" ;;
                create) customer_group_create "$@" ;;
                *) echo "Unknown customer-group action: $action" >&2; exit 1 ;;
            esac
            ;;
        customer-event)
            local action="${1:-create}"
            shift || true
            case "$action" in
                create) customer_event_create "$@" ;;
                *) echo "Unknown customer-event action: $action" >&2; exit 1 ;;
            esac
            ;;
        helpcenter)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) helpcenter_list ;;
                get) helpcenter_get "$@" ;;
                create) helpcenter_create "$@" ;;
                update) helpcenter_update "$@" ;;
                articles) helpcenter_articles "$@" ;;
                article)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_article_get "$@" ;;
                        get-by-slug) helpcenter_article_get_by_slug "$@" ;;
                        upsert) helpcenter_article_upsert "$@" ;;
                        delete) helpcenter_article_delete "$@" ;;
                        *) echo "Unknown article action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                group)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_group_get "$@" ;;
                        create) helpcenter_group_create "$@" ;;
                        update) helpcenter_group_update "$@" ;;
                        delete) helpcenter_group_delete "$@" ;;
                        *) echo "Unknown group action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                *) echo "Unknown helpcenter action: $action" >&2; exit 1 ;;
            esac
            ;;
        workspace)
            workspace_get
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown resource: $resource" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
