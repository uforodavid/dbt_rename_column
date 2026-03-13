{#
    _get_column_audit_query
    =======================
    Returns the appropriate INFORMATION_SCHEMA query based on the
    active adapter (Snowflake or BigQuery).

    Args:
        old_columns: list of column names to search for
#}

{% macro _get_column_audit_query(old_columns) %}
    {{ return(adapter.dispatch('_get_column_audit_query', 'dbt_rename_columns')(old_columns)) }}
{% endmacro %}


{# ── Snowflake ── #}
{% macro snowflake___get_column_audit_query(old_columns) %}

    {% set column_list = old_columns | map('upper') | join("','") %}

    select
        table_schema,
        table_name,
        column_name
    from {{ target.database }}.information_schema.columns
    where table_schema = upper('{{ target.schema }}')
      and column_name in ('{{ column_list }}')
    order by table_schema, table_name, column_name

{% endmacro %}


{# ── BigQuery ── #}
{% macro bigquery___get_column_audit_query(old_columns) %}

    {% set column_list = old_columns | map('lower') | join("','") %}

    select
        table_schema,
        table_name,
        column_name
    from `{{ target.database }}`.`{{ target.schema }}`.INFORMATION_SCHEMA.COLUMNS
    where lower(column_name) in ('{{ column_list }}')
    order by table_schema, table_name, column_name

{% endmacro %}


{# ── Default / Postgres / Redshift fallback ── #}
{% macro default___get_column_audit_query(old_columns) %}

    {% set column_list = old_columns | map('lower') | join("','") %}

    select
        table_schema,
        table_name,
        column_name
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and lower(column_name) in ('{{ column_list }}')
    order by table_schema, table_name, column_name

{% endmacro %}
