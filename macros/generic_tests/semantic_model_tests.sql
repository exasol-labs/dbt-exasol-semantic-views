{#-
  Tests for an adopted semantic model, attached to a view model that adopt()
  adopts into it. Each reads the catalog with a plain SELECT, because a
  script's result set cannot be selected from in SQL; each returns the rows
  that fail.

  `model_name` is the ESV model the view is adopted into -- the argument of its
  adopt() post-hook. It is required: the dbt model is the view, and its name
  is the semantic view's, not the model's.
-#}

{% macro esv_model_name(model, model_name) -%}
  {%- if not model_name -%}
    {{ exceptions.raise_compiler_error(
         "exasol_semantic_views tests on " ~ model.identifier ~ " need model_name: the ESV"
         ~ " model the view is adopted into, as passed to adopt().") }}
  {%- endif -%}
  {{ return(exasol_semantic_views.sql_string(model_name)) }}
{%- endmacro %}


{#- No ERROR or PRECONDITION issue in the model's latest validation run. -#}
{% test validates_clean(model, model_name=none) %}
  SELECT SEVERITY, OBJECT_TYPE, OBJECT_NAME, RULE_CODE, MESSAGE
  FROM SEMANTIC_CATALOG.CURRENT_VALIDATION_ISSUES
  WHERE UPPER(MODEL_NAME) = UPPER({{ exasol_semantic_views.esv_model_name(model, model_name) }})
    AND SEVERITY IN ('ERROR', 'PRECONDITION')
{% endtest %}


{#- The model is ready for agents: published and validated with no error or
    precondition. A model the catalog does not have fails too. -#}
{% test agent_ready(model, model_name=none) %}
  {%- set name = exasol_semantic_views.esv_model_name(model, model_name) -%}
  SELECT {{ name }} AS MODEL_NAME,
         COALESCE(m.AGENT_READINESS, 'MISSING') AS AGENT_READINESS
  FROM DUAL
  LEFT JOIN SEMANTIC_AGENT.MODELS_FOR_AGENT m
    ON UPPER(m.MODEL_NAME) = UPPER({{ name }})
  WHERE COALESCE(m.AGENT_READINESS, 'MISSING') NOT IN ('VALID', 'WARNING')
{% endtest %}


{#- No view compiled from the model has been retired because its definition
    changed: a dashboard or BI tool reading it would get SEMANTIC_SURFACE_015. -#}
{% test no_retired_views(model, model_name=none) %}
  SELECT VIEW_SCHEMA, VIEW_NAME, OBJECT_NAME, RETIRED_AT
  FROM SEMANTIC_CATALOG.FROZEN_VIEWS
  WHERE UPPER(MODEL_NAME) = UPPER({{ exasol_semantic_views.esv_model_name(model, model_name) }})
    AND PRESENCE = 'RETIRED'
{% endtest %}
