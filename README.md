# dbt_rename_columns

A dbt package for safely renaming columns across your entire project — audit the blast radius with a dbt macro, then apply changes with a Python CLI.

## Installation

Add to your `packages.yml`:

```yaml
packages:
  - git: "https://github.com/daviddata/dbt_rename_columns.git"
    revision: v0.1.0
```

Then run:

```bash
dbt deps
```

## Quick Start

### 1. Define your renames

In your project's `dbt_project.yml`:

```yaml
vars:
  column_renames:
    platform: user_provider
    foo_bar: foobar
```

### 2. Audit the blast radius

Run the audit macro to see which warehouse tables/views have the target columns:

```bash
dbt run-operation rename_audit
```

This queries your warehouse's `INFORMATION_SCHEMA` and prints a report showing every model that contains columns matching your rename map.

### 3. Preview file changes (dry run)

```bash
python dbt_packages/dbt_rename_columns/scripts/rename_columns.py \
  --project-dir . \
  --dry-run
```

This scans all `.sql` and `.yml` files and shows exactly what would change — no files are modified.

### 4. Apply the renames

```bash
python dbt_packages/dbt_rename_columns/scripts/rename_columns.py \
  --project-dir .
```

This creates backup files (`.rename_backup`) and applies the renames.

### 5. Verify and compile

```bash
dbt compile
dbt run   # optional: run in dev to confirm
```

### 6. Clean up and commit

```bash
# Remove backup files
python dbt_packages/dbt_rename_columns/scripts/rename_columns.py \
  --project-dir . \
  --clean-backups

# Remove the column_renames var from dbt_project.yml (one-time operation)
# Commit and push your branch
```

## Rollback

If something goes wrong:

```bash
python dbt_packages/dbt_rename_columns/scripts/rename_columns.py \
  --project-dir . \
  --rollback
```

This restores all files from their `.rename_backup` copies.

## How It Works

### Audit Macro

- Queries `INFORMATION_SCHEMA.COLUMNS` to find materialized models containing target columns
- Adapter-aware: works with Snowflake, BigQuery, and Postgres/Redshift
- Reports schema, table, current column name, and proposed new name

### Python Rename Script

- Scans `.sql` and `.yml` files in your project (skips `target/`, `dbt_packages/`, `.git/`, etc.)
- Uses word-boundary matching to avoid partial replacements (e.g., renaming `platform` won't touch `platform_id`)
- Preserves casing (PLATFORM → USER_PROVIDER, platform → user_provider)
- Creates backups before modifying files
- Supports dry run, rollback, and backup cleanup

## Supported Warehouses

| Warehouse | Audit Macro | Python Script |
|-----------|------------|---------------|
| Snowflake | ✅ | ✅ |
| BigQuery  | ✅ | ✅ |
| Postgres  | ✅ | ✅ |
| Redshift  | ✅ | ✅ |

## CLI Reference

```
python scripts/rename_columns.py [OPTIONS]

Options:
  --project-dir PATH   Path to dbt project root (default: .)
  --dry-run            Preview changes without modifying files
  --no-backup          Skip creating backup files
  --rollback           Restore files from .rename_backup copies
  --clean-backups      Remove all .rename_backup files
```
