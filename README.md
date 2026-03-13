# dbt_rename_column

A dbt package for safely renaming columns across your entire project — no manual find-and-replace across files.

Works in **dbt Cloud** and local environments. No warehouse connection required.

## Installation

Add to your `packages.yml`:

```yaml
packages:
  - git: "https://github.com/uforodavid/dbt_rename_column.git"
    revision: v0.1.0
```

Then run:

```bash
dbt deps
```

---

## Workflow

### 1. Define your renames

In your project's `dbt_project.yml`:

```yaml
vars:
  column_renames:
    platform: user_provider
    foo_bar: foobar
```

### 2. Audit the blast radius

```bash
dbt run-operation rename_audit
```

Scans the raw SQL of every model in your project and lists which files reference the columns you want to rename. Works in dbt Cloud with no warehouse connection.

> Uses simple string matching, so it may flag files where the column name appears inside a longer word (e.g. `platform` may also flag `platform_id`). The rename script uses word-boundary matching for precise replacement.

### 3. Apply the renames

Choose the method that fits your setup:

---

#### Option A — Run locally (recommended)

If you have the project cloned on your machine:

```bash
# Preview changes first
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --dry-run

# Apply
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir .
```

Requires Python and `pip install pyyaml`.

---

#### Option B — GitHub Actions (dbt Cloud users)

If you use dbt Cloud and don't run the project locally, use the included GitHub Actions workflow to apply renames directly from the GitHub UI:

1. Copy `.github/workflows/rename_columns.yml` from this package into your dbt project repo
2. Go to **Actions → Rename Columns → Run workflow** in GitHub
3. Enter your repo name and branch, set **dry run = true** to preview first
4. Re-run with **dry run = false** to apply and auto-commit the changes

The workflow requires a `GH_PAT` secret (a GitHub Personal Access Token with repo write access) added to your repo's Actions secrets.

---

### 4. Verify

```bash
dbt compile
dbt run   # optional: run in dev to confirm
```

### 5. Clean up and commit

```bash
# Remove backup files (if you ran locally)
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --clean-backups

# Remove the column_renames var from dbt_project.yml
# Commit and push your branch
```

---

## Rollback

If something goes wrong after applying locally:

```bash
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --rollback
```

Restores all files from their `.rename_backup` copies.

---

## How It Works

### Audit Macro (`rename_audit`)

- Scans `graph.nodes` — the parsed dbt project graph
- Checks the raw SQL of every model, seed, and snapshot for column name references
- No warehouse connection, no `dbt compile` needed
- Available in dbt Cloud via `dbt run-operation rename_audit`

### Python Rename Script

- Scans all `.sql` and `.yml` files in your project (skips `target/`, `dbt_packages/`, `.git/`, etc.)
- Uses word-boundary regex to avoid partial replacements (`platform` won't touch `platform_id`)
- Preserves casing (`PLATFORM` → `USER_PROVIDER`, `platform` → `user_provider`)
- Creates backups before modifying files
- Supports dry run, rollback, and backup cleanup

---

## CLI Reference

```
python dbt_packages/dbt_rename_column/scripts/rename_columns.py [OPTIONS]

Options:
  --project-dir PATH   Path to dbt project root (default: .)
  --dry-run            Preview changes without modifying files
  --no-backup          Skip creating backup files
  --rollback           Restore files from .rename_backup copies
  --clean-backups      Remove all .rename_backup files
```
