# Changelog

## 0.2.0 - 2026-11-14

A semantic view is now a dbt view model. Requires exasol-semantic-views 0.7.1
or later, the first release of ADOPT_VIEW with a published bundle (the
`v0.7.0` tag carries the same scripts, but its release build failed).

**Breaking.** The `exasol_semantic_model` materialization is gone, and with it
`split_statements`, `prepare_statement`, `relation_args`, the
`definition_unchanged` test and its `ESV_BUILDS` build record. A model built
with it is not removed; adopt its views instead, or keep authoring a semantic
model over several entities and relationships with exasol-semantic-views'
scripts and Semantic DDL, which no longer have a dbt wrapper here. The tests
now need `model_name`, the ESV model a view is adopted into.

- `adopt(esv_model)`: the post-hook that makes a view model a semantic view,
  rendering `EXECUTE SCRIPT SEMANTIC_ADMIN.ADOPT_VIEW(...)` for the model's
  schema and name. With `persist_docs`, the model's documentation becomes the
  semantic view's descriptions. Every build adopts again, so the semantic view
  follows the view, and dbt's threads may adopt several views at once.
- `query`, `compile_sql`, `validates_clean`, `agent_ready` and
  `no_retired_views` are unchanged, apart from the tests' `model_name`.
- `definition_unchanged` has no successor: adoption re-syncs on every build,
  so a change made outside dbt is overwritten by the next one.

## 0.1.0 - 2026-11-05

First release.

- `exasol_semantic_model` materialization: one ESV model per model file, its
  body ESV SQL with `ref()` for sources; rebuilt, validated and published on
  every run, failing the node on any refusal, including one reported in a
  `STATUS` column.
- `relation_args` for passing a dbt relation to an admin script.
- `query` and `compile_sql` for governed metrics in downstream models.
- Tests: `validates_clean`, `agent_ready`, `no_retired_views`,
  `definition_unchanged`.
- Requires exasol-semantic-views 0.6.1 or later.
