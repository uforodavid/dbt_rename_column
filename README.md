# dbt_rename_column

A dbt package for safely renaming columns across your entire project — no manual find-and-replace across files.

No warehouse connection required. Works entirely from your local project files and the dbt manifest.

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

## How to Rename a Column

### 1. Define your renames

In your project's `dbt_project.yml`:

```yaml
vars:
  column_renames:
    platform: user_provider
    foo_bar: foobar
```

### 2. Compile your project

```bash
dbt compile
```

This generates `target/manifest.json`, which the audit macro reads to find documented columns.

### 3. Audit the blast radius

```bash
dbt run-operation rename_audit
```

This scans your manifest and prints every **documented** column (defined in `schema.yml`) that matches your rename map. No warehouse connection needed.

> **Note:** Columns used only as SQL aliases (e.g. `'value' as platform`) won't appear in the manifest unless documented in a `schema.yml`. The Python script in step 4 will still find and rename them.

### 4. Preview file changes (dry run)

```bash
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --dry-run
```

This scans all `.sql` and `.yml` files and shows exactly what would change — no files are modified. This is the most complete view of the rename impact.

### 5. Apply the renames

```bash
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir .
```

This creates backup files (`.rename_backup`) and applies the renames across all files.

### 6. Verify

```bash
dbt compile
dbt run   # optional: run in dev to confirm
```

### 7. Clean up and commit

```bash
# Remove backup files
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --clean-backups

# Remove the column_renames var from dbt_project.yml
# Commit and push your branch
```

## Rollback

If something goes wrong after applying:

```bash
python dbt_packages/dbt_rename_column/scripts/rename_columns.py \
  --project-dir . \
  --rollback
```

This restores all files from their `.rename_backup` copies.

## How It Works

### Audit Macro (`rename_audit`)

- Reads `target/manifest.json` — no warehouse connection required
- Finds columns documented in `schema.yml` files that match your rename map
- Run `dbt compile` first to ensure the manifest is up to date

### Python Rename Script

- Scans all `.sql` and `.yml` files in your project (skips `target/`, `dbt_packages/`, `.git/`, etc.)
- Finds every column reference including undocumented SQL aliases
- Uses word-boundary matching to avoid partial replacements (e.g. `platform` won't touch `platform_id`)
- Preserves casing (`PLATFORM` → `USER_PROVIDER`, `platform` → `user_provider`)
- Creates backups before modifying files
- Supports dry run, rollback, and backup cleanup

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
