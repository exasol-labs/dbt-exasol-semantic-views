{#-
  Governed metrics in a downstream dbt model.

  The compiled SQL is inlined into the model, so the model needs neither the
  session preprocessor nor rights to call the compiler at query time, and it
  answers with the model as built in this run:

    -- depends_on: {{ ref('sales_semantic') }}
    {{ exasol_semantic_views.query(
         model='sales', object='SALES',
         metrics=['total_revenue'], dimensions=['customer_region'],
         filters=[{'field': 'order_status', 'op': '=', 'value': 'COMPLETE'}]) }}

  The `depends_on` comment orders the downstream model after the semantic
  model's build; the compile happens at run time, so a ref() alone in the call
  would not reach the parser.

  query() takes the structured request -- COMPILE_REQUEST_JSON's closed contract:
  metrics, dimensions, filters, having, order_by, limit. compile_sql() takes a
  Semantic SQL statement instead, as COMPILE_SQL accepts it.

  A refusal fails the model with the compiler's rule code and message. At parse
  time, when nothing may run, both return a placeholder.
-#}

{% macro query(model, object, metrics=[], dimensions=[], filters=[], having=[], order_by=[], limit=none) -%}
  {{ return(adapter.dispatch('query', 'exasol_semantic_views')(
       model, object, metrics, dimensions, filters, having, order_by, limit)) }}
{%- endmacro %}

{% macro default__query(model, object, metrics, dimensions, filters, having, order_by, limit) -%}
  {%- set request = {'model': model, 'object': object, 'metrics': metrics,
                     'dimensions': dimensions, 'client': 'dbt:exasol_semantic_views'} -%}
  {%- if filters %}{% do request.update({'filters': filters}) %}{% endif -%}
  {%- if having %}{% do request.update({'having': having}) %}{% endif -%}
  {%- if order_by %}{% do request.update({'order_by': order_by}) %}{% endif -%}
  {%- if limit is not none %}{% do request.update({'limit': limit}) %}{% endif -%}
  {%- set generated = exasol_semantic_views.compiled(
       "COMPILE_REQUEST_JSON(" ~ exasol_semantic_views.sql_string(tojson(request)) ~ ")",
       model ~ "." ~ object) -%}
  {%- if not execute -%}{{ return(generated) }}{%- endif -%}
  {#- The structured compile names each column exactly as the field is named,
      quoted -- "customer_region" -- so a table built from it has columns that
      unquoted SQL cannot reach. Each is re-aliased to the name an unquoted
      identifier folds to; quoting the upper-case name keeps a field named
      like a reserved word legal. -#}
  {%- set columns = [] -%}
  {%- for field in dimensions + metrics -%}
    {%- do columns.append('"' ~ field ~ '" AS "' ~ (field | upper) ~ '"') -%}
  {%- endfor -%}
  {{ return("SELECT " ~ (columns | join(", ")) ~ " FROM (\n" ~ generated ~ "\n) esv_query") }}
{%- endmacro %}


{% macro compile_sql(semantic_sql) -%}
  {{ return(adapter.dispatch('compile_sql', 'exasol_semantic_views')(semantic_sql)) }}
{%- endmacro %}

{% macro default__compile_sql(semantic_sql) -%}
  {{ return(exasol_semantic_views.compiled(
       "COMPILE_SQL(" ~ exasol_semantic_views.sql_string(semantic_sql) ~ ")", semantic_sql[:80])) }}
{%- endmacro %}


{#- Runs one compile script and returns GENERATED_SQL, read by column name. -#}
{% macro compiled(call, label) -%}
  {%- if not execute -%}
    {{ return("SELECT 1 AS PLACEHOLDER FROM DUAL") }}
  {%- endif -%}
  {%- set result = run_query("EXECUTE SCRIPT SEMANTIC_ADMIN." ~ call) -%}
  {%- set names = result.column_names | map('upper') | list -%}
  {%- set row = result.rows[0] -%}
  {%- if (row[names.index('STATUS')] | string | upper) != 'OK' -%}
    {{ exceptions.raise_compiler_error("exasol_semantic_views could not compile " ~ label ~ ": "
         ~ row[names.index('STATUS')] ~ " " ~ (row[names.index('ERROR_CODE')] or '') ~ " "
         ~ (row[names.index('ERROR_MESSAGE')] or row[names.index('CLARIFICATION_JSON')] or '')) }}
  {%- endif -%}
  {{ return(row[names.index('GENERATED_SQL')]) }}
{%- endmacro %}
