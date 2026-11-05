# Changelog

## 0.1.0 - unreleased

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
