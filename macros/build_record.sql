{#-
  What each build deployed.

  The catalog is the authoritative store, and it can be changed without
  touching the repository: an edit made by hand after a build changes the
  model dbt reports as built. Each build records the model's definition hash,
  and the `definition_unchanged` test compares the live hash with the last
  recorded one -- so out-of-band drift fails CI, and the next build restores
  the repository's version.

  The table lives in var('exasol_semantic_views:audit_schema'), by default the
  target schema.
-#}

{% macro audit_relation() -%}
  {{ return(adapter.dispatch('audit_relation', 'exasol_semantic_views')()) }}
{%- endmacro %}

{% macro default__audit_relation() -%}
  {%- set schema = var('exasol_semantic_views:audit_schema', target.schema) -%}
  {{ return(api.Relation.create(schema=schema, identifier='ESV_BUILDS', type='table')) }}
{%- endmacro %}


{% macro record_build(model_name) -%}
  {%- set audit = exasol_semantic_views.audit_relation() -%}
  {%- do run_query("CREATE SCHEMA IF NOT EXISTS " ~ audit.schema) -%}
  {%- do run_query("CREATE TABLE IF NOT EXISTS " ~ audit ~ " ("
                   ~ " MODEL_NAME VARCHAR(256), MODEL_HASH VARCHAR(128),"
                   ~ " BUILT_AT TIMESTAMP, INVOCATION_ID VARCHAR(64))") -%}
  {%- do run_query("INSERT INTO " ~ audit ~ " SELECT MODEL_NAME, DEFINITION_HASH, CURRENT_TIMESTAMP, "
                   ~ exasol_semantic_views.sql_string(invocation_id)
                   ~ " FROM SEMANTIC_AGENT.DEFINITION_HASHES_FOR_AGENT"
                   ~ " WHERE FIELD_KIND = 'MODEL' AND UPPER(MODEL_NAME) = UPPER("
                   ~ exasol_semantic_views.sql_string(model_name) ~ ")") -%}
{%- endmacro %}
