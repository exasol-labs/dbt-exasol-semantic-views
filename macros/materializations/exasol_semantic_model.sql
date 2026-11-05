{#-
  One exasol-semantic-views model, rebuilt from its definition.

  The body is ESV SQL -- the `EXECUTE SCRIPT SEMANTIC_ADMIN.*` calls and
  `ALTER SEMANTIC VIEW` statements an administrator would write -- with ref()
  wherever a source is named, so the semantic model is a node in the DAG
  downstream of the tables it reads. The model itself is created from config,
  so the body starts with its entities.

  A run drops the model and replays the body from a clean slate, then validates
  and publishes: the deployed model is a function of the repository, and a
  definition removed from the body is removed from the database. The published
  views are re-created, so a view another tool froze over them is dropped with
  the schema.

  Config, under `meta: {exasol_semantic_views: {...}}`, because dbt v2 refuses
  custom keys at the top level of a config:

    model_name        ESV model name; defaults to this dbt model's name
    published_schema  schema the guarded views are published in; required
    description       model description
    owner_role        owning role recorded on the model
    grant_roles       roles given access with GRANT_MODEL_ROLE after publishing
    query_timeout     session QUERY_TIMEOUT for the build, in seconds (default 60;
                      multi-representation probes refuse 0, dbt's default)
    publish           false to validate without publishing (default true)
-#}

{% materialization exasol_semantic_model, adapter='exasol' %}
  {%- set settings = exasol_semantic_views.model_settings(model) -%}
  {%- set target_relation = this.incorporate(type='view') -%}

  {{ run_hooks(pre_hooks) }}
  {{ exasol_semantic_views.require_runtime() }}

  {%- set previous_timeout = exasol_semantic_views.session_parameter('QUERY_TIMEOUT') -%}
  {%- do run_query("ALTER SESSION SET QUERY_TIMEOUT=" ~ settings.query_timeout) -%}

  {%- set name = exasol_semantic_views.sql_string(settings.model_name) -%}
  {{ exasol_semantic_views.run_admin('drop', "DROP_MODEL_IF_EXISTS(" ~ name ~ ")") }}
  {{ exasol_semantic_views.run_admin('create', "CREATE_MODEL(" ~ name ~ ", "
       ~ exasol_semantic_views.sql_string(settings.published_schema) ~ ", "
       ~ exasol_semantic_views.sql_string(settings.description) ~ ", "
       ~ exasol_semantic_views.sql_string(settings.owner_role) ~ ")") }}

  {%- for statement in exasol_semantic_views.split_statements(sql) -%}
    {{ exasol_semantic_views.run_statement(loop.index, exasol_semantic_views.prepare_statement(statement)) }}
  {%- endfor -%}

  {{ exasol_semantic_views.validate(settings.model_name) }}
  {%- if settings.publish -%}
    {{ exasol_semantic_views.run_admin('publish', "PUBLISH_MODEL(" ~ name ~ ")") }}
    {%- for role in settings.grant_roles -%}
      {{ exasol_semantic_views.run_admin('grant ' ~ role, "GRANT_MODEL_ROLE(" ~ name ~ ", "
           ~ exasol_semantic_views.sql_string(role) ~ ")") }}
    {%- endfor -%}
  {%- endif -%}
  {{ exasol_semantic_views.record_build(settings.model_name) }}

  {%- do run_query("ALTER SESSION SET QUERY_TIMEOUT=" ~ (previous_timeout or 0)) -%}

  {#- dbt reports the node by its main statement. -#}
  {%- call statement('main') -%}
    SELECT 1 FROM DUAL
  {%- endcall -%}
  {{ run_hooks(post_hooks) }}
  {%- do adapter.commit() -%}
  {{ return({'relations': []}) }}
{% endmaterialization %}


{% macro model_settings(node) -%}
  {%- set esv = (node.config.get('meta') or {}).get('exasol_semantic_views', {}) -%}
  {%- if not esv.get('published_schema') -%}
    {{ exceptions.raise_compiler_error(
         "exasol_semantic_model " ~ node.name ~ ": meta.exasol_semantic_views.published_schema"
         ~ " is required -- the schema the model's guarded views are published in.") }}
  {%- endif -%}
  {%- set roles = esv.get('grant_roles', []) -%}
  {{ return({
       'model_name': esv.get('model_name', node.name),
       'published_schema': esv.get('published_schema'),
       'description': esv.get('description', node.description or none),
       'owner_role': esv.get('owner_role'),
       'grant_roles': [roles] if roles is string else roles,
       'query_timeout': esv.get('query_timeout', 60) | int,
       'publish': esv.get('publish', true),
     }) }}
{%- endmacro %}


{#- Fails the run when the database does not carry the scripts this package
    calls, naming the release that added them, rather than failing half way
    through a build on a missing script. -#}
{% macro require_runtime() -%}
  {%- set needed = ['DROP_MODEL_IF_EXISTS', 'APPLY_SEMANTIC_DEFINITION_OR_FAIL',
                    'APPLY_FUSION_DECLARATION_OR_FAIL', 'COMPILE_REQUEST_JSON'] -%}
  {%- set found = run_query("SELECT SCRIPT_NAME FROM SYS.EXA_ALL_SCRIPTS WHERE SCRIPT_SCHEMA = 'SEMANTIC_ADMIN'"
                            ~ " AND SCRIPT_NAME IN ('" ~ (needed | join("', '")) ~ "')") -%}
  {%- set have = found.columns[0].values() | list -%}
  {%- set lacking = needed | reject('in', have) | list -%}
  {%- if lacking | length > 0 -%}
    {{ exceptions.raise_compiler_error(
         "exasol_semantic_views needs exasol-semantic-views 0.6.1 or later; this database"
         ~ " lacks SEMANTIC_ADMIN." ~ (lacking | join(', SEMANTIC_ADMIN.'))
         ~ ". Install a newer release, or check that this user can see SEMANTIC_ADMIN.") }}
  {%- endif -%}
{%- endmacro %}


{% macro session_parameter(name) -%}
  {%- set result = run_query("SELECT SESSION_VALUE FROM EXA_PARAMETERS WHERE PARAMETER_NAME = "
                             ~ exasol_semantic_views.sql_string(name)) -%}
  {{ return(result.rows[0][0] if result.rows | length > 0 else none) }}
{%- endmacro %}


{#- Runs one admin script. -#}
{% macro run_admin(label, call) -%}
  {{ exasol_semantic_views.run_statement(label, "EXECUTE SCRIPT SEMANTIC_ADMIN." ~ call) }}
{%- endmacro %}


{#- Runs one statement and fails the node if it was refused.

    A script that raises fails the statement on its own. Several report a
    refusal in a STATUS column instead, and dbt counts a statement that
    returned rows as one that succeeded -- so a returned ERROR row is turned
    into a failure here, naming the step and the rule code. -#}
{% macro run_statement(label, statement) -%}
  {%- set result = run_query(statement) -%}
  {%- set names = result.column_names | map('upper') | list if result is not none else [] -%}
  {%- if 'STATUS' in names -%}
    {%- set status_at = names.index('STATUS') -%}
    {%- for row in result.rows if (row[status_at] | string | upper) == 'ERROR' -%}
      {%- set code = row[names.index('ERROR_CODE')] if 'ERROR_CODE' in names else '' -%}
      {%- set message_column = 'ERROR_MESSAGE' if 'ERROR_MESSAGE' in names else 'MESSAGE' -%}
      {%- set message = row[names.index(message_column)] if message_column in names else '' -%}
      {{ exceptions.raise_compiler_error("exasol_semantic_model step " ~ label ~ " was refused: "
           ~ (code or '') ~ " " ~ (message or '') ~ "\n  statement: " ~ statement[:500]) }}
    {%- endfor -%}
  {%- endif -%}
  {{ log("  [exasol_semantic_views] " ~ label ~ ": ok", info=False) }}
{%- endmacro %}


{#- VALIDATE_MODEL reports issues as rows; an ERROR or PRECONDITION fails the
    node with every blocking rule named, warnings are logged. -#}
{% macro validate(model_name) -%}
  {%- set result = run_query("EXECUTE SCRIPT SEMANTIC_ADMIN.VALIDATE_MODEL("
                             ~ exasol_semantic_views.sql_string(model_name) ~ ")") -%}
  {%- set names = result.column_names | map('upper') | list -%}
  {%- set blocking = [] -%}
  {%- for row in result.rows -%}
    {%- set severity = row[names.index('SEVERITY')] | string | upper -%}
    {%- set issue = row[names.index('RULE_CODE')] ~ " [" ~ row[names.index('OBJECT_NAME')] ~ "]: "
                    ~ row[names.index('MESSAGE')] -%}
    {%- if severity in ('ERROR', 'PRECONDITION') -%}
      {%- do blocking.append(issue) -%}
    {%- else -%}
      {{ log("  [exasol_semantic_views] " ~ severity ~ " " ~ issue, info=False) }}
    {%- endif -%}
  {%- endfor -%}
  {%- if blocking | length > 0 -%}
    {{ exceptions.raise_compiler_error("exasol_semantic_model " ~ model_name ~ " failed validation with "
         ~ (blocking | length) ~ " blocking issue(s):\n  " ~ (blocking | join("\n  "))) }}
  {%- endif -%}
{%- endmacro %}
