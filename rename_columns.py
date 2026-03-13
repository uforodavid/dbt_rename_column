#!/usr/bin/env python3
"""
dbt Column Rename Tool
======================
Finds and replaces column names across all .sql and .yml files
in a dbt project, based on the rename map defined in dbt_project.yml.

Usage:
    # Preview changes (no files modified):
    python scripts/rename_columns.py --project-dir /path/to/dbt/project --dry-run

    # Apply changes (creates backups):
    python scripts/rename_columns.py --project-dir /path/to/dbt/project

    # Apply without backups:
    python scripts/rename_columns.py --project-dir /path/to/dbt/project --no-backup

    # Rollback from backups:
    python scripts/rename_columns.py --project-dir /path/to/dbt/project --rollback
"""

import argparse
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Tuple

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


# ─── Configuration ───────────────────────────────────────────────────────────

BACKUP_SUFFIX = ".rename_backup"
TARGET_EXTENSIONS = {".sql", ".yml", ".yaml"}
SKIP_DIRS = {"target", "dbt_packages", "dbt_modules", "logs", ".git", "node_modules", "__pycache__"}
SKIP_FILES = {"dbt_project.yml", "packages.yml"}


# ─── Core Logic ──────────────────────────────────────────────────────────────

def load_rename_map(project_dir: Path) -> Dict[str, str]:
    """Load column_renames var from dbt_project.yml."""
    dbt_project_path = project_dir / "dbt_project.yml"

    if not dbt_project_path.exists():
        print(f"ERROR: dbt_project.yml not found at {dbt_project_path}")
        sys.exit(1)

    with open(dbt_project_path, "r") as f:
        project_config = yaml.safe_load(f)

    rename_map = project_config.get("vars", {}).get("column_renames", {})

    if not rename_map:
        print("⚠  No column_renames defined in dbt_project.yml vars.")
        print("   Example:")
        print("     vars:")
        print("       column_renames:")
        print("         platform: user_provider")
        print("         foo_bar: foobar")
        sys.exit(0)

    return rename_map


def find_target_files(project_dir: Path) -> List[Path]:
    """Walk the project directory and collect .sql and .yml files."""
    files = []
    for root, dirs, filenames in os.walk(project_dir):
        # Skip excluded directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        for filename in filenames:
            if filename in SKIP_FILES:
                continue
            filepath = Path(root) / filename
            if filepath.suffix in TARGET_EXTENSIONS:
                files.append(filepath)

    return sorted(files)


def build_rename_patterns(rename_map: Dict[str, str]) -> List[Tuple[re.Pattern, str, str, str]]:
    """
    Build regex patterns for each rename.

    For .sql files, we use word-boundary matching to catch column
    references in SELECT, WHERE, JOIN, GROUP BY, etc.

    Returns list of (compiled_pattern, replacement, old_name, new_name).
    """
    patterns = []

    for old_name, new_name in rename_map.items():
        # SQL pattern: word-boundary match, case-insensitive
        # Matches: platform, t.platform, "platform", `platform`
        # Avoids: user_platform (prefix), platform_id (suffix)
        sql_pattern = re.compile(
            r'(?<![a-zA-Z0-9_])'   # not preceded by word char
            + re.escape(old_name)
            + r'(?![a-zA-Z0-9_])',  # not followed by word char
            re.IGNORECASE
        )
        patterns.append((sql_pattern, new_name, old_name, new_name))

    return patterns


def apply_renames_to_content(
    content: str,
    patterns: List[Tuple[re.Pattern, str, str, str]],
    filepath: Path
) -> Tuple[str, List[dict]]:
    """
    Apply all rename patterns to file content.

    For YAML files, only renames in structural positions:
      - `- name: column_name` lines
      - `name: column_name` lines
    Descriptions and other free text are left untouched.

    For SQL files, renames all word-boundary matches.

    Returns (new_content, list_of_changes).
    """
    is_yaml = filepath.suffix in {".yml", ".yaml"}
    lines = content.split("\n")
    changes = []
    new_lines = []

    # Pattern to detect YAML name fields: "  - name: value" or "  name: value"
    yaml_name_pattern = re.compile(r'^(\s*-?\s*name\s*:\s*)(.+)$')

    for line_num, line in enumerate(lines, start=1):
        original_line = line

        if is_yaml:
            # Only rename on lines that define a `name:` field
            name_match = yaml_name_pattern.match(line)
            if name_match:
                prefix = name_match.group(1)
                value = name_match.group(2)
                for pattern, replacement, old_name, new_name in patterns:
                    value = pattern.sub(
                        _case_preserving_replacer(replacement), value
                    )
                line = prefix + value
        else:
            # SQL files: rename all word-boundary matches
            for pattern, replacement, old_name, new_name in patterns:
                line = pattern.sub(
                    _case_preserving_replacer(replacement), line
                )

        if line != original_line:
            changes.append({
                "file": str(filepath),
                "line_number": line_num,
                "old_text": original_line.strip(),
                "new_text": line.strip(),
            })

        new_lines.append(line)

    return "\n".join(new_lines), changes


def _case_preserving_replacer(replacement: str):
    """Return a replacement function that preserves the original casing."""
    def replace_fn(match):
        matched = match.group(0)
        if matched.isupper():
            return replacement.upper()
        elif matched.islower():
            return replacement.lower()
        else:
            return replacement
    return replace_fn


# ─── File Operations ─────────────────────────────────────────────────────────

def create_backup(filepath: Path) -> Path:
    """Create a backup of the file before modifying it."""
    backup_path = filepath.with_suffix(filepath.suffix + BACKUP_SUFFIX)
    shutil.copy2(filepath, backup_path)
    return backup_path


def rollback_backups(project_dir: Path) -> int:
    """Restore all backup files."""
    count = 0
    for root, dirs, filenames in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in filenames:
            if filename.endswith(BACKUP_SUFFIX):
                backup_path = Path(root) / filename
                original_path = Path(str(backup_path).replace(BACKUP_SUFFIX, ""))
                shutil.copy2(backup_path, original_path)
                backup_path.unlink()
                count += 1
    return count


def clean_backups(project_dir: Path) -> int:
    """Remove all backup files after successful rename."""
    count = 0
    for root, dirs, filenames in os.walk(project_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in filenames:
            if filename.endswith(BACKUP_SUFFIX):
                (Path(root) / filename).unlink()
                count += 1
    return count


# ─── CLI ─────────────────────────────────────────────────────────────────────

def print_report(all_changes: List[dict], rename_map: Dict[str, str], dry_run: bool):
    """Print the rename report."""
    mode = "DRY RUN" if dry_run else "APPLIED"

    print()
    print("═" * 70)
    print(f"  COLUMN RENAME REPORT ({mode})")
    print("═" * 70)
    print()
    print("  Rename map:")
    for old, new in rename_map.items():
        print(f"    {old} → {new}")
    print()

    if not all_changes:
        print("  ✅ No matching columns found in project files.")
        print("═" * 70)
        return

    # Group by file
    files_changed = {}
    for change in all_changes:
        f = change["file"]
        if f not in files_changed:
            files_changed[f] = []
        files_changed[f].append(change)

    for filepath, changes in files_changed.items():
        print(f"  📄 {filepath}")
        for c in changes:
            print(f"     L{c['line_number']:>4}:")
            print(f"       - {c['old_text']}")
            print(f"       + {c['new_text']}")
        print()

    print("─" * 70)
    print(f"  Total: {len(all_changes)} change(s) across {len(files_changed)} file(s)")
    print("═" * 70)

    if dry_run:
        print()
        print("  This was a dry run. No files were modified.")
        print("  To apply changes, run without --dry-run")
        print()


def main():
    parser = argparse.ArgumentParser(
        description="Find and replace column names across a dbt project."
    )
    parser.add_argument(
        "--project-dir",
        type=str,
        default=".",
        help="Path to the dbt project root (default: current directory)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Skip creating backup files before renaming",
    )
    parser.add_argument(
        "--rollback",
        action="store_true",
        help="Restore files from backup (.rename_backup files)",
    )
    parser.add_argument(
        "--clean-backups",
        action="store_true",
        help="Remove all .rename_backup files",
    )

    args = parser.parse_args()
    project_dir = Path(args.project_dir).resolve()

    # Handle rollback
    if args.rollback:
        count = rollback_backups(project_dir)
        print(f"✅ Rolled back {count} file(s) from backups.")
        return

    # Handle backup cleanup
    if args.clean_backups:
        count = clean_backups(project_dir)
        print(f"🧹 Removed {count} backup file(s).")
        return

    # Load config
    rename_map = load_rename_map(project_dir)
    print(f"📋 Loaded {len(rename_map)} rename(s) from dbt_project.yml")

    # Find files
    target_files = find_target_files(project_dir)
    print(f"🔍 Scanning {len(target_files)} file(s)...")

    # Build patterns
    patterns = build_rename_patterns(rename_map)

    # Process files
    all_changes = []

    for filepath in target_files:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        new_content, changes = apply_renames_to_content(content, patterns, filepath)

        if changes:
            all_changes.extend(changes)

            if not args.dry_run:
                # Create backup unless skipped
                if not args.no_backup:
                    create_backup(filepath)

                # Write modified content
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(new_content)

    # Report
    print_report(all_changes, rename_map, args.dry_run)

    if not args.dry_run and all_changes:
        print("  ✅ Changes applied successfully.")
        if not args.no_backup:
            print("  💾 Backups created with .rename_backup extension.")
            print("  🔄 To undo: python scripts/rename_columns.py --rollback")
            print("  🧹 To clean up backups: python scripts/rename_columns.py --clean-backups")
        print()


if __name__ == "__main__":
    main()
