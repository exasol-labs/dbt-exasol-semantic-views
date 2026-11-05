<div align="center">

<h1>exasol_semantic_views</h1>

<p><em>A dbt package for <a href="https://github.com/exasol-labs/exasol-semantic-views">Exasol Semantic Views</a>.<br>Build, validate, publish, test and query a governed semantic layer — as part of your dbt project, in plain SQL.</em></p>

[![CI](https://github.com/exasol-labs/dbt-exasol-semantic-views/actions/workflows/ci.yml/badge.svg)](https://github.com/exasol-labs/dbt-exasol-semantic-views/actions/workflows/ci.yml)
[![dbt](https://img.shields.io/badge/dbt-1.10%2B-FF694B?logo=dbt&logoColor=white)](https://docs.getdbt.com)
[![Exasol Semantic Views](https://img.shields.io/badge/Exasol%20Semantic%20Views-0.6.1%2B-003865)](https://github.com/exasol-labs/exasol-semantic-views)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**[Install](#install) · [Define a model](#define-a-semantic-model) · [Test it](#test-it) · [Query it](#query-it-from-a-dbt-model) · [Config](#config) · [Development](#development)**

</div>

---

The semantic layer becomes part of the project: a model file per semantic
model, written in the same SQL an administrator would run, with `ref()` for
every source. `dbt build` rebuilds it after the tables it reads, validates it,
publishes it, tests it, and builds the marts that query it — in DAG order, with
selection and state comparison working as for any other model.

**Supported warehouse: Exasol only**, through
[dbt-exasol](https://github.com/exasol/dbt-exasol) 1.10 or later. Requires
exasol-semantic-views **0.6.1** or later; the package checks at run time and
names what is missing.

## Install

```yaml
# packages.yml
packages:
  - package: exasol-labs/exasol_semantic_views
    version: [">=0.1.0", "<0.2.0"]
```

## Define a semantic model

One model file per ESV model, materialized as `exasol_semantic_model`. The body
is ESV SQL — `EXECUTE SCRIPT SEMANTIC_ADMIN.*` calls for the graph and
`ALTER SEMANTIC VIEW` for each object's dimensions, facts and metrics —
separated by semicolons. The model itself is created from the config, so the
body starts with its entities.

```sql
-- models/semantic/sales.sql
{{ config(
    materialized='exasol_semantic_model',
    meta={'exasol_semantic_views': {
        'published_schema': 'SEMANTIC_SALES',
        'description': 'Certified sales model',
        'grant_roles': ['ANALYST'],
    }}
) }}

EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_ENTITY('sales', 'customer',
  {{ exasol_semantic_views.relation_args(ref('customers')) }},
  'c', 'c.CUSTOMER_KEY', 'One row per customer', 'Customers');
EXECUTE SCRIPT SEMANTIC_ADMIN.ADD_SEMANTIC_OBJECT('sales', 'ORDERS', 'order', 'Orders');
-- ... keys, relationships, fusion (APPLY_FUSION_DECLARATION_OR_FAIL) ...

ALTER SEMANTIC VIEW sales.ORDERS
REPLACE DIMENSIONS (
  DIMENSION customer_region ON ENTITY customer AS c.REGION RETURNS VARCHAR(20) PUBLIC
)
REPLACE METRICS (
  METRIC total_revenue AS SUM(net_amount) ON ENTITY "order"
    RETURNS DECIMAL(18,2) ADDITIVE PUBLIC CERTIFIED
);
```

`relation_args(ref(...))` passes a dbt model as the `'SCHEMA', 'OBJECT'` pair
the scripts take, which is what puts the semantic model downstream of it in the
DAG. dbt renders names as written; ESV resolves them to the database's
spelling.

### What a run does

1. Checks the database carries the scripts the package calls.
2. Sets `QUERY_TIMEOUT` for the build (multi-representation probes refuse
   dbt's default of 0), and restores it afterwards.
3. `DROP_MODEL_IF_EXISTS`, then `CREATE_MODEL` from the config.
4. Runs the body, one statement at a time. `ALTER SEMANTIC VIEW` goes through
   `APPLY_SEMANTIC_DEFINITION_OR_FAIL`. A statement that raises fails the node;
   so does one that reports `STATUS = 'ERROR'` in its result instead of
   raising — dbt would otherwise count it a success.
5. `VALIDATE_MODEL`; an `ERROR` or `PRECONDITION` fails the node with every
   blocking rule named.
6. `PUBLISH_MODEL`, then `GRANT_MODEL_ROLE` for each `grant_roles` entry.
7. Records the deployed definition hash for `definition_unchanged`.

**Every run is a rebuild from a clean slate.** The deployed model is a function
of the repository, and a definition removed from the file is removed from the
database. The cost: the published schema is dropped and re-created, so a query
running against it during the build fails, and a database view another tool
created over a semantic object is dropped with it. A build that fails leaves
the model as far as it got, not as it was; the next successful build restores
it.

### Config

Under `meta: {exasol_semantic_views: {...}}` (dbt v2 refuses custom keys at the
top level of a config):

| Key | Default | Meaning |
|---|---|---|
| `published_schema` | required | Schema the guarded views are published in |
| `model_name` | the dbt model's name | ESV model name |
| `description` | the model's description | Model description |
| `owner_role` | none | Owning role recorded on the model |
| `grant_roles` | `[]` | Roles given access after publishing |
| `query_timeout` | `60` | Session `QUERY_TIMEOUT` during the build, seconds |
| `publish` | `true` | `false` validates without publishing |

## Test it

```yaml
models:
  - name: sales
    data_tests:
      - exasol_semantic_views.validates_clean        # no ERROR/PRECONDITION issue
      - exasol_semantic_views.agent_ready            # AGENT_READINESS is VALID or WARNING
      - exasol_semantic_views.no_retired_views       # no frozen view retired by a definition change
      - exasol_semantic_views.definition_unchanged   # nobody edited it outside dbt since the build
```

Each takes `model_name` when the ESV model name differs from the dbt model's.
`definition_unchanged` reads the build record in
`var('exasol_semantic_views:audit_schema')` (default: the target schema), table
`ESV_BUILDS`.

## Query it from a dbt model

```sql
-- models/marts/revenue_by_region.sql
-- depends_on: {{ ref('sales') }}
{{ exasol_semantic_views.query(
     model='sales', object='ORDERS',
     metrics=['total_revenue'], dimensions=['customer_region'],
     filters=[{'field': 'order_status', 'op': '=', 'value': 'COMPLETE'}],
     order_by=[{'field': 'total_revenue', 'direction': 'desc'}]) }}
```

The request is compiled at run time with `COMPILE_REQUEST_JSON` and the
governed SQL is inlined, so the model needs no session preprocessor and answers
with the semantic model as built in this run. Columns are the requested fields,
upper-cased. The `depends_on` comment is what orders it after the semantic
model: the compile happens at run time, where dbt's parser cannot see it.

`exasol_semantic_views.compile_sql("SELECT ... FROM SEMANTIC_SALES.ORDERS GROUP BY ...")`
does the same for a Semantic SQL statement, through `COMPILE_SQL`.

A request the compiler refuses fails the model with its rule code.

## Overriding

Every public macro is dispatched in the `exasol_semantic_views` namespace:

```yaml
# dbt_project.yml
dispatch:
  - macro_namespace: exasol_semantic_views
    search_order: ['my_project', 'exasol_semantic_views']
```

then define `exasol__split_statements`, `exasol__audit_relation`, ... in your
project.

## Development

`integration_tests/` is a dbt project that installs this package from `../`,
builds a semantic model over seeded tables, queries it both ways, and checks the
answers against the same numbers computed by hand:

```sh
cd integration_tests
DBT_PROFILES_DIR=. dbt deps
DBT_PROFILES_DIR=. dbt build
```

It needs an Exasol database with exasol-semantic-views installed; set
`EXASOL_DSN`, `EXASOL_USER` and `DBT_ENV_SECRET_EXASOL_PASSWORD`.
