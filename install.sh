#!/usr/bin/env bash
# =============================================================================
# push-review installer
# =============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template ruby
#   curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template rails
#   curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template nextjs
#
# Available templates: base, node, typescript, ruby, rails, nextjs
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}${BOLD}[push-review]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[push-review]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[push-review]${RESET} ⚠  $*"; }
error()   { echo -e "${RED}${BOLD}[push-review]${RESET} ✗  $*"; exit 1; }
divider() { echo -e "${CYAN}──────────────────────────────────────────────${RESET}"; }

# ── Remote URLs ───────────────────────────────────────────────────────────────
REPO_BASE_URL="https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main"
HOOK_URL="${REPO_BASE_URL}/hook/pre-push"
TEMPLATES_URL="${REPO_BASE_URL}/templates"
TEMPLATE="base"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --template)
      TEMPLATE=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      shift 2
      ;;
    *)
      error "Unknown argument: $1. Usage: --template <name>. Available: base, node, typescript, ruby, rails, nextjs"
      ;;
  esac
done

TEMPLATE_URL="${TEMPLATES_URL}/${TEMPLATE}.yml"

# ── Validate git repository ───────────────────────────────────────────────────
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  error "Not inside a git repository. Run this from the root of your project."
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK_DEST="$HOOKS_DIR/pre-push"
CONFIG_DEST="$REPO_ROOT/.push-review.yml"

divider
info "Installing push-review..."
echo -e "  Template: ${BOLD}${TEMPLATE}${RESET}"
divider

# ── Check for curl ────────────────────────────────────────────────────────────
if ! command -v curl >/dev/null 2>&1; then
  error "curl is required but not found."
fi

# ── Download and install hook ─────────────────────────────────────────────────
info "Downloading hook script..."
HOOK_TMP=$(mktemp)
trap 'rm -f "$HOOK_TMP"' EXIT

if ! curl -fsSL "$HOOK_URL" -o "$HOOK_TMP"; then
  error "Failed to download hook from ${HOOK_URL}"
fi

if ! head -1 "$HOOK_TMP" | grep -q 'bash'; then
  error "Downloaded hook does not appear to be a valid shell script."
fi

if ! bash -n "$HOOK_TMP"; then
  error "Downloaded hook has a syntax error. Please report this at https://github.com/rootstrap/ai-git-hooks."
fi

# Extract the version from the downloaded hook before installing
HOOK_VERSION=$(grep 'HOOK_VERSION=' "$HOOK_TMP" | head -1 | sed 's/.*HOOK_VERSION="\([^"]*\)".*/\1/')

if [ -f "$HOOK_DEST" ]; then
  BACKUP="${HOOK_DEST}.backup.$(date +%Y%m%d%H%M%S)"
  warn "Existing pre-push hook found. Backing up to ${BACKUP}"
  cp "$HOOK_DEST" "$BACKUP"
fi

cp "$HOOK_TMP" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
success "Hook installed (v${HOOK_VERSION}) ✓"

# ── Download config template ──────────────────────────────────────────────────
if [ -f "$CONFIG_DEST" ]; then
  warn ".push-review.yml already exists. Skipping config download."
  warn "To reset to the ${TEMPLATE} template, delete .push-review.yml and re-run."
else
  info "Downloading ${TEMPLATE} config template..."
  CONFIG_TMP=$(mktemp)
  trap 'rm -f "$HOOK_TMP" "$CONFIG_TMP"' EXIT

  if ! curl -fsSL "$TEMPLATE_URL" -o "$CONFIG_TMP"; then
    error "Failed to download template '${TEMPLATE}' from ${TEMPLATE_URL}."
  fi

  cp "$CONFIG_TMP" "$CONFIG_DEST"
  success "Config written to .push-review.yml ✓"
fi

# ── Check for Claude Code CLI ─────────────────────────────────────────────────
divider
info "Checking dependencies..."

if command -v claude >/dev/null 2>&1; then
  CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
  success "Claude Code CLI found (${CLAUDE_VERSION}) ✓"
else
  warn "Claude Code CLI not found."
  warn "The hook will block pushes until it is installed and authenticated."
  warn "Install:      ${BOLD}curl -fsSL https://claude.ai/install.sh | bash${RESET}"
  warn "Authenticate: ${BOLD}claude /login${RESET}"
fi

# ── Check runtimes declared in config ─────────────────────────────────────────
if [ -f "$CONFIG_DEST" ]; then
  TOOL_BINARIES=$(awk '
    /^tools:/{flag=1;next}
    flag && /^[a-z]/{flag=0}
    flag && /^[[:space:]]*command:/{
      sub(/^[[:space:]]*command:[[:space:]]*/, "")
      gsub(/"/, "")
      split($0, a, " ")
      print a[1]
    }
  ' "$CONFIG_DEST" | sort -u)

  checked_runtimes=""
  while IFS= read -r binary; do
    [ -z "$binary" ] && continue
    case "$binary" in
      npx|yarn|node) runtime="node" ;;
      bundle|ruby)   runtime="ruby" ;;
      python|python3) runtime="python3" ;;
      go)            runtime="go" ;;
      *)             runtime="$binary" ;;
    esac
    case "$checked_runtimes" in
      *"$runtime"*) continue ;;
    esac
    checked_runtimes="$checked_runtimes $runtime"
    if command -v "$runtime" >/dev/null 2>&1; then
      runtime_version=$("$runtime" --version 2>/dev/null || echo "unknown")
      success "${runtime} found (${runtime_version}) ✓"
    else
      warn "${runtime} not found — tools using '${binary}' will fail at review time."
    fi
  done <<EOF
$TOOL_BINARIES
EOF
fi

# ── Done ──────────────────────────────────────────────────────────────────────
divider
echo -e "${GREEN}${BOLD}  push-review v${HOOK_VERSION} installed successfully!${RESET}"
divider
echo ""
echo -e "  Edit ${BOLD}.push-review.yml${RESET} to configure tools and review behaviour."
echo -e "  Skip checks when needed: ${BOLD}git push --no-verify${RESET}"
echo ""