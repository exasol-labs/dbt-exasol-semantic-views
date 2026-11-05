{#-
  Tests for a deployed semantic model, attached to its exasol_semantic_model
  node. Each reads the catalog with a plain SELECT, because a script's result
  set cannot be selected from in SQL; each returns the rows that fail.

  `model_name` defaults to the node's name, which is also the ESV model name
  unless meta.exasol_semantic_views.model_name says otherwise -- then pass it.
-#}

{#- No ERROR or PRECONDITION issue in the model's latest validation run. -#}
{% test validates_clean(model, model_name=none) %}
  SELECT SEVERITY, OBJECT_TYPE, OBJECT_NAME, RULE_CODE, MESSAGE
  FROM SEMANTIC_CATALOG.CURRENT_VALIDATION_ISSUES
  WHERE UPPER(MODEL_NAME) = UPPER({{ exasol_semantic_views.sql_string(model_name or model.identifier) }})
    AND SEVERITY IN ('ERROR', 'PRECONDITION')
{% endtest %}


{#- The model is ready for agents: published and validated with no error or
    precondition. A model the catalog does not have fails too. -#}
{% test agent_ready(model, model_name=none) %}
  SELECT {{ exasol_semantic_views.sql_string(model_name or model.identifier) }} AS MODEL_NAME,
         COALESCE(m.AGENT_READINESS, 'MISSING') AS AGENT_READINESS
  FROM DUAL
  LEFT JOIN SEMANTIC_AGENT.MODELS_FOR_AGENT m
    ON UPPER(m.MODEL_NAME) = UPPER({{ exasol_semantic_views.sql_string(model_name or model.identifier) }})
  WHERE COALESCE(m.AGENT_READINESS, 'MISSING') NOT IN ('VALID', 'WARNING')
{% endtest %}


{#- No view compiled from the model has been retired because its definition
    changed: a dashboard or BI tool reading it would get SEMANTIC_SURFACE_015. -#}
{% test no_retired_views(model, model_name=none) %}
  SELECT VIEW_SCHEMA, VIEW_NAME, OBJECT_NAME, RETIRED_AT
  FROM SEMANTIC_CATALOG.FROZEN_VIEWS
  WHERE UPPER(MODEL_NAME) = UPPER({{ exasol_semantic_views.sql_string(model_name or model.identifier) }})
    AND PRESENCE = 'RETIRED'
{% endtest %}


{#- The deployed model is the one the last build deployed: its definition hash
    equals the hash recorded then. An edit made in the database by hand, not
    through the repository, fails this until the next build restores it. -#}
{% test definition_unchanged(model, model_name=none) %}
  {%- set name = exasol_semantic_views.sql_string(model_name or model.identifier) -%}
  {%- set audit = exasol_semantic_views.audit_relation() -%}
  WITH last_build AS (
    SELECT MODEL_HASH FROM {{ audit }}
    WHERE UPPER(MODEL_NAME) = UPPER({{ name }})
    ORDER BY BUILT_AT DESC
    LIMIT 1
  ), live AS (
    SELECT DEFINITION_HASH FROM SEMANTIC_AGENT.DEFINITION_HASHES_FOR_AGENT
    WHERE FIELD_KIND = 'MODEL' AND UPPER(MODEL_NAME) = UPPER({{ name }})
  )
  SELECT (SELECT MODEL_HASH FROM last_build) AS BUILT_HASH,
         (SELECT DEFINITION_HASH FROM live) AS LIVE_HASH
  FROM DUAL
  WHERE (SELECT MODEL_HASH FROM last_build) IS NULL
     OR (SELECT DEFINITION_HASH FROM live) IS NULL
     OR (SELECT MODEL_HASH FROM last_build) <> (SELECT DEFINITION_HASH FROM live)
{% endtest %}
