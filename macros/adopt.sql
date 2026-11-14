{#-
  A dbt view model as an exasol-semantic-views semantic view.

  An aggregate view over one table -- plain columns, aggregates, GROUP BY --
  already says what a semantic view is: its plain columns are dimensions, its
  aggregates metrics, its table the entity. SEMANTIC_ADMIN.ADOPT_VIEW reads the
  view from the database and makes it one, with the descriptions dbt's
  persist_docs wrote as comments. So the whole integration is a post-hook:

    models:
      my_project:
        semantic:
          +materialized: view
          +persist_docs: {relation: true, columns: true}
          +post-hook: "{{ exasol_semantic_views.adopt('sales') }}"

  adopt('sales') renders

    EXECUTE SCRIPT SEMANTIC_ADMIN.ADOPT_VIEW('sales', '<this.schema>', '<this.identifier>')

  which could as well be written out by hand. ADOPT_VIEW creates the model when
  it does not exist, validates and publishes it, and raises on any refusal, so
  a view it cannot adopt fails its node. Run on every build, it follows the
  view: an unchanged view changes nothing, a removed column retires its metric.

  Before rendering, it checks that the database has ADOPT_VIEW, so an older
  exasol-semantic-views fails the node naming the release it needs rather than
  with "script not found".
-#}

{% macro adopt(esv_model) -%}
  {{ return(adapter.dispatch('adopt', 'exasol_semantic_views')(esv_model)) }}
{%- endmacro %}

{% macro default__adopt(esv_model) -%}
  {%- if execute -%}{{ exasol_semantic_views.require_runtime() }}{%- endif -%}
  {{ return("EXECUTE SCRIPT SEMANTIC_ADMIN.ADOPT_VIEW("
            ~ exasol_semantic_views.sql_string(esv_model) ~ ", "
            ~ exasol_semantic_views.sql_string(this.schema) ~ ", "
            ~ exasol_semantic_views.sql_string(this.identifier) ~ ")") }}
{%- endmacro %}


{#- Fails the node when the database lacks a script this package calls, naming
    the release that added it. One catalog read per adopted view. -#}
{% macro require_runtime() -%}
  {%- if not execute -%}{{ return('') }}{%- endif -%}
  {%- set needed = ['ADOPT_VIEW', 'COMPILE_REQUEST_JSON', 'COMPILE_SQL'] -%}
  {%- set found = run_query("SELECT SCRIPT_NAME FROM SYS.EXA_ALL_SCRIPTS WHERE SCRIPT_SCHEMA = 'SEMANTIC_ADMIN'"
                            ~ " AND SCRIPT_NAME IN ('" ~ (needed | join("', '")) ~ "')") -%}
  {%- set have = found.columns[0].values() | list -%}
  {%- set lacking = needed | reject('in', have) | list -%}
  {%- if lacking | length > 0 -%}
    {{ exceptions.raise_compiler_error(
         "exasol_semantic_views needs exasol-semantic-views 0.7.1 or later; this database"
         ~ " lacks SEMANTIC_ADMIN." ~ (lacking | join(', SEMANTIC_ADMIN.'))
         ~ ". Install a newer release, or check that this user can see SEMANTIC_ADMIN.") }}
  {%- endif -%}
{%- endmacro %}


{#- A SQL string literal. -#}
{% macro sql_string(value) -%}
  {%- if value is none -%}{{ return('NULL') }}{%- endif -%}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{%- endmacro %}
