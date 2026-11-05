{#-
  Turning a model body into the statements Exasol runs.

  A semantic model's body is ESV SQL as an administrator would write it: a
  sequence of `EXECUTE SCRIPT SEMANTIC_ADMIN.*` calls and `ALTER SEMANTIC VIEW`
  statements, separated by semicolons. Exasol runs one statement per request,
  so the body is split here, honouring quotes and comments, and each statement
  is run on its own.
-#}

{% macro split_statements(sql) -%}
  {{ return(adapter.dispatch('split_statements', 'exasol_semantic_views')(sql)) }}
{%- endmacro %}

{% macro default__split_statements(sql) -%}
  {#- One pass over the characters. A semicolon ends a statement only outside a
      string literal, a quoted identifier and a comment; comments are dropped,
      so a statement that is only a comment is never sent. -#}
  {%- set state = namespace(statements=[], current='', mode='code', previous='') -%}
  {%- for ch in (sql ~ '\n') -%}
    {%- if state.mode == 'line_comment' -%}
      {%- if ch == '\n' -%}{%- set state.mode = 'code' -%}{%- set state.current = state.current ~ ch -%}{%- endif -%}
    {%- elif state.mode == 'block_comment' -%}
      {%- if state.previous == '*' and ch == '/' -%}{%- set state.mode = 'code' -%}{%- set ch = '' -%}{%- endif -%}
    {%- elif state.mode == 'single' -%}
      {%- set state.current = state.current ~ ch -%}
      {%- if ch == "'" -%}{%- set state.mode = 'code' -%}{%- endif -%}
    {%- elif state.mode == 'double' -%}
      {%- set state.current = state.current ~ ch -%}
      {%- if ch == '"' -%}{%- set state.mode = 'code' -%}{%- endif -%}
    {%- elif ch == '-' and state.previous == '-' -%}
      {%- set state.current = state.current[:-1] -%}
      {%- set state.mode = 'line_comment' -%}
    {%- elif ch == '*' and state.previous == '/' -%}
      {%- set state.current = state.current[:-1] -%}
      {%- set state.mode = 'block_comment' -%}
      {%- set ch = '' -%}
    {%- elif ch == ';' -%}
      {%- if state.current | trim -%}{%- do state.statements.append(state.current | trim) -%}{%- endif -%}
      {%- set state.current = '' -%}
    {%- else -%}
      {%- set state.current = state.current ~ ch -%}
      {%- if ch == "'" -%}{%- set state.mode = 'single' -%}
      {%- elif ch == '"' -%}{%- set state.mode = 'double' -%}{%- endif -%}
    {%- endif -%}
    {#- A doubled quote closes and reopens the literal, which is the same
        string; `previous` is cleared after a comment opener so `/*/` does
        not close it. -#}
    {%- set state.previous = ch -%}
  {%- endfor -%}
  {%- if state.current | trim -%}{%- do state.statements.append(state.current | trim) -%}{%- endif -%}
  {{ return(state.statements) }}
{%- endmacro %}


{#- `ALTER SEMANTIC VIEW` needs the session preprocessor when sent as it is.
    Sent through APPLY_SEMANTIC_DEFINITION_OR_FAIL instead, it needs no session
    setup and a refusal raises. Every other statement is sent unchanged. -#}
{% macro prepare_statement(statement) -%}
  {{ return(adapter.dispatch('prepare_statement', 'exasol_semantic_views')(statement)) }}
{%- endmacro %}

{% macro default__prepare_statement(statement) -%}
  {%- set words = statement.split() -%}
  {%- if words | length >= 3 and (words[:3] | join(' ') | upper) == 'ALTER SEMANTIC VIEW' -%}
    {{ return("EXECUTE SCRIPT SEMANTIC_ADMIN.APPLY_SEMANTIC_DEFINITION_OR_FAIL("
              ~ exasol_semantic_views.sql_string(statement) ~ ", FALSE)") }}
  {%- endif -%}
  {{ return(statement) }}
{%- endmacro %}


{#- A SQL string literal. -#}
{% macro sql_string(value) -%}
  {%- if value is none -%}{{ return('NULL') }}{%- endif -%}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{%- endmacro %}


{#- A relation as the two string arguments the admin scripts take for a
    source: `'SCHEMA', 'OBJECT'`. Use it wherever a script names a source, so
    the source is a ref() and dbt knows the semantic model reads it:

      EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_ENTITY('sales', 'customer',
        {{ exasol_semantic_views.relation_args(ref('customers')) }}, 'c', ...);

    The names go as dbt renders them. exasol-semantic-views resolves them to
    the database's spelling, so a lower-case model name needs no folding. -#}
{% macro relation_args(relation) -%}
  {{ return(exasol_semantic_views.sql_string(relation.schema) ~ ", "
            ~ exasol_semantic_views.sql_string(relation.identifier)) }}
{%- endmacro %}
