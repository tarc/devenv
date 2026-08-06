#!/usr/bin/env bash

set -euo pipefail

# proactive-agent.HARNESS.1
# Already running inside the devenv shell; nesting another `devenv shell` here
# would discard the module input the test harness set up.
acai skill --install

# proactive-agent.TESTS.1
# The agent, in devenv terms, is the definition the claude module generates.
# These checks query that definition directly; they never call out to Claude,
# so they need no credentials and stay deterministic in CI.
ACID="proactive-agent.TESTS.1"
AGENT="assist"
AGENTS_DIR=".claude/agents"
SETTINGS=".claude/settings.json"
WORKFLOW_AGENTS=(supervise prepare-tasks implement review-task)

fail() {
  echo "FAIL [$ACID] $1" >&2
  exit 1
}

pass() {
  echo "ok   [$ACID] $1"
}

# Print the YAML frontmatter of a generated agent definition.
frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---" { exit }
       inside { print }' "$1"
}

frontmatter_has() {
  frontmatter "$1" | grep -qxF "$2"
}

echo "=== $ACID: querying the generated definition of the '$AGENT' agent ==="

# 1. The agent is registered.
agent_file="$AGENTS_DIR/$AGENT.md"
if [ ! -e "$agent_file" ]; then
  echo "Contents of $AGENTS_DIR:" >&2
  ls -la "$AGENTS_DIR" >&2 || true
  fail "agent '$AGENT' is not registered: $agent_file does not exist"
fi
pass "agent '$AGENT' is registered at $agent_file"

# 2. It declares itself proactive.
if ! frontmatter_has "$agent_file" "proactive: true"; then
  echo "Frontmatter of $agent_file:" >&2
  frontmatter "$agent_file" >&2
  fail "agent '$AGENT' does not declare 'proactive: true'"
fi
pass "agent '$AGENT' declares 'proactive: true'"

# 3. It is not the primary agent.
if [ ! -e "$SETTINGS" ]; then
  fail "$SETTINGS does not exist"
fi
# `|| true` keeps an unmatched grep from aborting the script under `set -euo
# pipefail`, so the empty-value branch below stays reachable and reports why.
primary=$(grep -o '"agent"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
if [ -z "$primary" ]; then
  echo "Contents of $SETTINGS:" >&2
  cat "$SETTINGS" >&2
  fail "no primary agent recorded in $SETTINGS"
fi
if [ "$primary" = "$AGENT" ]; then
  fail "agent '$AGENT' is the primary agent in $SETTINGS, it must not be"
fi
if [ "$primary" != "supervise" ]; then
  fail "expected the primary agent in $SETTINGS to be 'supervise', found '$primary'"
fi
pass "agent '$AGENT' is not primary; the primary agent is '$primary'"

# 4. It is distinct from the four workflow agents, which are all still intact.
for workflow_agent in "${WORKFLOW_AGENTS[@]}"; do
  if [ "$AGENT" = "$workflow_agent" ]; then
    fail "agent '$AGENT' must not be one of the workflow agents"
  fi

  workflow_file="$AGENTS_DIR/$workflow_agent.md"
  if [ ! -e "$workflow_file" ]; then
    fail "workflow agent '$workflow_agent' is missing: $workflow_file does not exist"
  fi
  if ! frontmatter_has "$workflow_file" "name: $workflow_agent"; then
    fail "workflow agent '$workflow_agent' no longer declares 'name: $workflow_agent'"
  fi
  if frontmatter_has "$workflow_file" "proactive: true"; then
    fail "workflow agent '$workflow_agent' became proactive, only '$AGENT' should be"
  fi
done
pass "agent '$AGENT' is distinct from ${WORKFLOW_AGENTS[*]}, which are all still present and non-proactive"

# 5. Its tools grant the capabilities of proactive-agent.EXAMPLES.1.
for tool in Read Grep Glob Bash WebFetch; do
  if ! frontmatter_has "$agent_file" "  - $tool"; then
    echo "Frontmatter of $agent_file:" >&2
    frontmatter "$agent_file" >&2
    fail "proactive-agent.EXAMPLES.1: agent '$AGENT' is not granted the '$tool' tool"
  fi
done
for tool in Write Edit; do
  if frontmatter_has "$agent_file" "  - $tool"; then
    fail "proactive-agent.EXAMPLES.1: agent '$AGENT' is granted the authoring tool '$tool', which belongs to the 'implement' agent"
  fi
done
pass "proactive-agent.EXAMPLES.1: agent '$AGENT' is granted Read, Grep, Glob, Bash and WebFetch, and no authoring tools"

echo "=== $ACID: all checks passed ==="
