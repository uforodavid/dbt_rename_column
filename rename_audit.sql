{#
    rename_audit
    ============
    Queries the warehouse's INFORMATION_SCHEMA to identify every
    model / column pair that matches the rename map defined in
    `var('column_renames')`.

    Usage:
      dbt run-operation rename_audit

    Output:
      A table printed to stdout listing:
        - schema.table
        - current column name
        - proposed new column name
#}

{% macro rename_audit() %}

    {% set rename_map = var('column_renames', {}) %}

    {% if rename_map | length == 0 %}
        {{ log("⚠  No renames defined. Set `column_renames` var in dbt_project.yml.", info=True) }}
        {{ return([]) }}
    {% endif %}

    {# Build the list of old column names to search for #}
    {% set old_columns = rename_map.keys() | list %}

    {% set query = _get_column_audit_query(old_columns) %}

    {% set results = run_query(query) %}

    {% if results | length == 0 %}
        {{ log("✅  No columns found matching the rename map. Nothing to do.", info=True) }}
        {{ return([]) }}
    {% endif %}

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
    {{ log("  %-40s %-25s %-25s" | format("MODEL", "CURRENT COLUMN", "NEW COLUMN"), info=True) }}
    {{ log("───────────────────────────────────────────────────────────────", info=True) }}

    {% set audit_results = [] %}

    {% for row in results %}
        {% set schema_name = row['TABLE_SCHEMA'] if 'TABLE_SCHEMA' in row.column_names else row['table_schema'] %}
        {% set table_name = row['TABLE_NAME'] if 'TABLE_NAME' in row.column_names else row['table_name'] %}
        {% set column_name = row['COLUMN_NAME'] if 'COLUMN_NAME' in row.column_names else row['column_name'] %}

        {# Normalize to lowercase for matching #}
        {% set col_lower = column_name | lower %}

        {% if col_lower in rename_map %}
            {% set new_name = rename_map[col_lower] %}
            {% set model_ref = schema_name ~ "." ~ table_name %}

            {{ log("  %-40s %-25s %-25s" | format(model_ref, column_name, new_name), info=True) }}

            {% do audit_results.append({
                'schema': schema_name,
                'table': table_name,
                'current_column': column_name,
                'new_column': new_name
            }) %}
        {% endif %}
    {% endfor %}

    {{ log("───────────────────────────────────────────────────────────────", info=True) }}
    {{ log("  Total: " ~ audit_results | length ~ " column(s) across " ~ (audit_results | map(attribute='table') | list | unique | list | length) ~ " model(s)", info=True) }}
    {{ log("═══════════════════════════════════════════════════════════════", info=True) }}
    {{ log("", info=True) }}
    {{ log("  Next step: run the Python rename script to apply changes:", info=True) }}
    {{ log("    python scripts/rename_columns.py --project-dir . --dry-run", info=True) }}
    {{ log("", info=True) }}

    {{ return(audit_results) }}

{% endmacro %}
