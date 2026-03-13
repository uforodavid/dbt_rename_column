{#
    rename_audit
    ============
    Scans the raw SQL of every model in the dbt graph and produces
    a report of every file that references the columns to be renamed,
    plus step-by-step find-and-replace instructions for dbt Cloud IDE.

    No warehouse connection required. No dbt compile required.
    Works natively in dbt Cloud.

    Usage:
      dbt run-operation rename_audit

    After running, use the printed instructions to apply renames using
    dbt Cloud IDE global find & replace (Ctrl+H → check "All Files").
#}

{% macro rename_audit() %}

    {% set rename_map = var('column_renames', {}) %}

    {% if rename_map | length == 0 %}
        {{ log("", info=True) }}
        {{ log("  No renames defined.", info=True) }}
        {{ log("  Add column_renames to your dbt_project.yml vars:", info=True) }}
        {{ log("", info=True) }}
        {{ log("    vars:", info=True) }}
        {{ log("      column_renames:", info=True) }}
        {{ log("        old_column_name: new_column_name", info=True) }}
        {{ log("", info=True) }}
        {{ return([]) }}
    {% endif %}

    {% set audit_results = {} %}

    {# Scan every model/seed/snapshot in the project graph #}
    {% for node_id, node in graph.nodes.items() %}
        {% if node.resource_type in ['model', 'seed', 'snapshot'] %}

            {% set raw_sql = node.raw_code if node.raw_code is defined else node.raw_sql %}
            {% set raw_sql_lower = raw_sql | lower %}

            {% for old_name in rename_map.keys() %}
                {% if old_name | lower in raw_sql_lower %}
                    {% if old_name not in audit_results %}
                        {% do audit_results.update({old_name: []}) %}
                    {% endif %}
                    {% do audit_results[old_name].append(node.path) %}
                {% endif %}
            {% endfor %}

        {% endif %}
    {% endfor %}

    {# ── Print Report ── #}
    {{ log("", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════════", info=True) }}
    {{ log("  COLUMN RENAME AUDIT REPORT", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════════", info=True) }}

    {% if audit_results | length == 0 %}
        {{ log("", info=True) }}
        {{ log("  No models reference the columns in your rename map.", info=True) }}
        {{ log("═══════════════════════════════════════════════════════════════════", info=True) }}
        {{ return([]) }}
    {% endif %}

    {% for old_name, new_name in rename_map.items() %}
        {% if old_name in audit_results %}

            {{ log("", info=True) }}
            {{ log("  ┌─ " ~ old_name ~ " → " ~ new_name, info=True) }}
            {{ log("  │", info=True) }}
            {{ log("  │  Found in " ~ audit_results[old_name] | length ~ " file(s):", info=True) }}
            {% for path in audit_results[old_name] %}
                {{ log("  │    • " ~ path, info=True) }}
            {% endfor %}
            {{ log("  │", info=True) }}
            {{ log("  │  To apply in dbt Cloud IDE:", info=True) }}
            {{ log("  │    1. Press Ctrl+H (or Cmd+H on Mac)", info=True) }}
            {{ log("  │    2. Check the 'All Files' / regex toggle", info=True) }}
            {{ log("  │    3. Find:    \\b" ~ old_name ~ "\\b", info=True) }}
            {{ log("  │       Replace: " ~ new_name, info=True) }}
            {{ log("  │    4. Review matches and click Replace All", info=True) }}
            {{ log("  └───────────────────────────────────────────────────────────", info=True) }}

        {% endif %}
    {% endfor %}

    {{ log("", info=True) }}
    {{ log("  Tip: the \\b in the Find field is a word boundary — it ensures", info=True) }}
    {{ log("  'platform' does not accidentally match 'platform_id'.", info=True) }}
    {{ log("  Enable regex mode in the find bar for word-boundary to work.", info=True) }}
    {{ log("", info=True) }}
    {{ log("  After replacing, run: dbt compile  to verify no errors.", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════════", info=True) }}
    {{ log("", info=True) }}

    {{ return(audit_results) }}

{% endmacro %}
