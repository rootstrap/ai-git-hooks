# ai-git-hooks / push-review

A language-agnostic `pre-push` hook that runs your linters and tests against changed files, then asks Claude to review the diff before every push.

## How it works

```
git push
    │
    ▼
┌─────────────────────────────────────┐
│  Changed files vs target branch     │
│  (ignore_paths filtering applied)   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Run configured tools               │
│  (linters, type checkers, tests)    │
│  ✗ any failure → push blocked       │
└──────────────┬──────────────────────┘
               │ all pass
               ▼
┌─────────────────────────────────────┐
│  AI review via Claude Code CLI      │
│  (diff sent, findings returned)     │
│  BLOCK → push blocked               │
│  PASS  → push proceeds              │
└─────────────────────────────────────┘
```

## Install

```bash
# Default (base template — no tools pre-configured, fully documented)
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash

# Node.js
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template node

# TypeScript
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template typescript

# Next.js
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template nextjs

# Ruby
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template ruby

# Ruby on Rails
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template rails
```

The installer:

1. Downloads and validates `hook/pre-push` → `.git/hooks/pre-push`
2. Backs up any existing `pre-push` hook before overwriting
3. Downloads the template config → `.push-review.yml` (only on first install — never overwrites)
4. Checks for Claude Code CLI and warns about missing runtimes

## Requirements

**Claude Code CLI** (required for AI review):

```bash
npm install -g @anthropic-ai/claude-code
claude /login
```

**Runtime dependencies** depend on the tools you configure:

| Runtime | Required by |
|---------|-------------|
| Node.js | `node`, `typescript`, `nextjs` templates |
| Ruby    | `ruby`, `rails` templates |
| Python  | Python tools (manual config) |
| Go      | Go tools (manual config) |

The installer checks which runtimes your config requires and warns about any that are missing. If Claude Code CLI is not installed, the hook still runs tool checks — it only skips the AI review step.

## Configuration

After install, edit `.push-review.yml` in your project root:

```yaml
agent:
  # Claude model used for AI review. Requires Claude Code CLI (claude /login).
  model: claude-sonnet-4-20250514

review:
  target_branch: main       # diff base: git diff <target_branch>...HEAD
  context_lines: 10         # surrounding context lines included in the diff
  max_lines_for_full_file: 300  # below this threshold, full file contents are sent
                                # instead of just the diff for richer context

  # Topics the AI reviewer focuses on
  focus:
    - security
    - logic_errors
    - test_coverage
    - performance
    - naming_and_readability

  # Findings in these categories block the push
  blocking_categories:
    - security
    - logic_errors

  # Findings in these categories are printed as warnings but never block
  warning_categories:
    - test_coverage
    - performance
    - naming_and_readability

# Tools to run before AI review — first failure blocks the push immediately
tools:
  - name: eslint
    command: npx eslint {changed_files}   # {changed_files} is replaced at runtime
    extensions: [".js", ".jsx", ".ts", ".tsx"]

  - name: brakeman
    command: bundle exec brakeman --no-pager --quiet
    # no {changed_files} → runs on the whole project

# Files and patterns excluded from tool checks and AI review
ignore_paths:
  - "*.lock"
  - "dist/**"
  - "coverage/**"
```

## Available templates

| `--template` | Stack | Tools pre-configured |
|---|---|---|
| `base` | Any | None (fully-documented reference config) |
| `node` | Node.js | ESLint, Prettier, Jest |
| `typescript` | TypeScript | tsc, ESLint, Prettier, Jest |
| `nextjs` | Next.js | tsc, next lint, Prettier, Jest |
| `ruby` | Ruby | RuboCop, Reek, RSpec |
| `rails` | Ruby on Rails | RuboCop, Reek, Brakeman, RSpec |

## Skip checks

To bypass the hook for a single push:

```bash
git push --no-verify
```

## Updating

Re-run the installer to update the hook script. Your `.push-review.yml` is **never overwritten** — it stays exactly as you've configured it.

```bash
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash
```

To also reset your config to a template, delete it first:

```bash
rm .push-review.yml
curl -fsSL https://raw.githubusercontent.com/rootstrap/ai-git-hooks/main/install.sh | bash -s -- --template <name>
```

## Contributing

To add a new template:

1. Add `templates/<name>.yml` following the structure of an existing template (e.g. `ruby.yml`)
2. Add a row to the **Available templates** table in this README
3. Open a pull request

Templates should include sensible `ignore_paths` defaults and pre-configured `tools` for the common tools in that stack. The `base.yml` template is the reference for all available config options.
