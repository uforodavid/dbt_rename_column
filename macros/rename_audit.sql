{#
    rename_audit
    ============
    Scans the raw SQL of every model, seed, and snapshot in the dbt
    graph to identify files that reference columns in the rename map.

    No warehouse connection required. No dbt compile required.
    Works in dbt Cloud and local environments.

    Usage:
      dbt run-operation rename_audit

    Output:
      A report listing every model whose SQL contains a column
      name from the rename map, plus the next steps to apply.

    Note:
      Uses simple string matching (not regex), so it may surface
      files where the column name appears inside a longer word
      (e.g. searching "platform" may also flag "platform_id").
      The Python script uses word-boundary matching for the actual
      precise replacement.
#}

{% macro rename_audit() %}

    {% set rename_map = var('column_renames', {}) %}

    {% if rename_map | length == 0 %}
        {{ log("  No renames defined. Set `column_renames` var in dbt_project.yml.", info=True) }}
        {{ return([]) }}
    {% endif %}

    {% set audit_results = [] %}
    {% set files_flagged = [] %}

    {{ log("", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════", info=True) }}
    {{ log("  COLUMN RENAME AUDIT REPORT", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════", info=True) }}
    {{ log("", info=True) }}
    {{ log("  Rename map:", info=True) }}
    {% for old_name, new_name in rename_map.items() %}
        {{ log("    " ~ old_name ~ " → " ~ new_name, info=True) }}
    {% endfor %}
    {{ log("", info=True) }}
    {{ log("───────────────────────────────────────────────────────────────", info=True) }}
    {{ log("  %-50s %s" | format("MODEL", "COLUMNS FOUND"), info=True) }}
    {{ log("───────────────────────────────────────────────────────────────", info=True) }}

    {% for node_id, node in graph.nodes.items() %}
        {% if node.resource_type in ['model', 'seed', 'snapshot'] %}

            {# raw_code in dbt >= 1.3, raw_sql in older versions #}
            {% set raw_sql = node.raw_code if node.raw_code is defined else node.raw_sql %}
            {% set raw_sql_lower = raw_sql | lower %}

            {% set matched_cols = [] %}
            {% for old_name in rename_map.keys() %}
                {% if old_name | lower in raw_sql_lower %}
                    {% do matched_cols.append(old_name ~ " → " ~ rename_map[old_name]) %}
                {% endif %}
            {% endfor %}

            {% if matched_cols | length > 0 %}
                {{ log("  %-50s %s" | format(node.path, matched_cols | join(", ")), info=True) }}
                {% do audit_results.append({
                    'model': node.path,
                    'matches': matched_cols
                }) %}
            {% endif %}

        {% endif %}
    {% endfor %}

    {% if audit_results | length == 0 %}
        {{ log("  No models reference the columns in your rename map.", info=True) }}
    {% endif %}

    {{ log("───────────────────────────────────────────────────────────────", info=True) }}
    {{ log("  " ~ audit_results | length ~ " model(s) flagged", info=True) }}
    {{ log("", info=True) }}
    {{ log("  Note: uses simple string matching — the Python script uses", info=True) }}
    {{ log("  word-boundary matching for precise replacement.", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════", info=True) }}
    {{ log("", info=True) }}
    {{ log("  Next step: run the Python script to preview exact file changes:", info=True) }}
    {{ log("    python dbt_packages/dbt_rename_column/scripts/rename_columns.py --project-dir . --dry-run", info=True) }}
    {{ log("", info=True) }}

    {{ return(audit_results) }}

{% endmacro %}
