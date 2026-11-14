<div align="center">

<h1>exasol_semantic_views</h1>

<p><em>Your semantic layer, defined in dbt.<br>Write a view you already know how to write — get governed metrics that are right at every grain, for BI tools, SQL users and AI agents alike.</em></p>

[![CI](https://github.com/exasol-labs/dbt-exasol-semantic-views/actions/workflows/ci.yml/badge.svg)](https://github.com/exasol-labs/dbt-exasol-semantic-views/actions/workflows/ci.yml)
[![dbt](https://img.shields.io/badge/dbt-1.10%2B-FF694B?logo=dbt&logoColor=white)](https://docs.getdbt.com)
[![Exasol Semantic Views](https://img.shields.io/badge/Exasol%20Semantic%20Views-0.7.1%2B-003865)](https://github.com/exasol-labs/exasol-semantic-views)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**[Install](#install) · [Define a semantic view](#define-a-semantic-view) · [Test it](#test-it) · [Query it](#query-it-from-a-dbt-model) · [Development](#development)**

</div>

---

Most semantic layers ask you to learn a new modelling language: a YAML spec, a
separate service to run, and a second copy of your business logic that slowly
drifts from the warehouse. This package goes the other way. **A semantic view
is a dbt view model** — plain SQL over one table, documented in the YAML you
already keep. Add one post-hook, and
[Exasol Semantic Views](https://github.com/exasol-labs/exasol-semantic-views)
turns it into governed metrics, inside the database:

```sql
-- models/semantic/shipping.sql: adopted as a semantic view on every dbt build
select ship_mode,
       sum(freight_amount)         as freight,
       count(distinct customer_id) as customers
from {{ ref('orders') }}
group by ship_mode
```

What that gives you that a view on its own cannot:

- **Right at every grain.** Ask for `customers` across all ship modes and a
  customer who shipped by air and by sea is counted once — not twice, as
  adding up the view's rows would. `COUNT(DISTINCT)`, averages and ratios are
  recomputed from the source rows at whatever grain someone asks for, so
  nobody double-counts by accident.
- **One definition for every consumer.** BI tools, SQL users and AI agents
  query the same governed metrics, with the descriptions from your dbt docs.
  Agents can discover what exists and get an answer, or a clear refusal, instead
  of guessing at joins.
- **Governed where the data lives.** Validation, publication, discovery and
  access control run in Exasol itself. There is no sidecar service to deploy,
  and no second copy of the logic to keep in sync.
- **Your whole semantic layer, in one dbt project, in plain SQL.** The view
  is the definition, versioned and reviewed like any other model, and
  rebuilt with `dbt build`. The rest of the layer — relationships between
  entities, data fusion across sources, grants — is Exasol Semantic Views SQL
  too, so it can live in the same project and run from the same hooks. Nothing
  new to learn, nothing extra to run.

**Supported warehouse: Exasol only**, through
[dbt-exasol](https://github.com/exasol/dbt-exasol) 1.10 or later. Requires
exasol-semantic-views **0.7.1** or later; the package checks at run time and
names what is missing.

## Install

```yaml
# packages.yml
packages:
  - package: exasol-labs/exasol_semantic_views
    version: [">=0.2.0", "<0.3.0"]
```

Or straight from GitHub, pinned to a release tag:

```yaml
packages:
  - git: https://github.com/exasol-labs/dbt-exasol-semantic-views.git
    revision: 0.2.0
```

Then `dbt deps`.

## Define a semantic view

Three lines in `dbt_project.yml` make every model in a folder a semantic view
of one ESV model:

```yaml
models:
  my_project:
    semantic:
      +materialized: view
      +persist_docs: {relation: true, columns: true}
      +post-hook: "{{ exasol_semantic_views.adopt('finance') }}"
```

Then each view model in that folder is one semantic view:

```sql
-- models/semantic/pnl.sql
select
    t.legal_entity,
    t.pnl_group_name,
    t.snapshot_date,
    sum(t.amount_eur)              as pnl_amount_eur,
    count(distinct t.booking_id)   as bookings
from {{ ref('fct_finance_pnl_transactions') }} t
group by t.legal_entity, t.pnl_group_name, t.snapshot_date
```

and its ordinary documentation is the semantic view's:

```yaml
# models/semantic/schema.yml
models:
  - name: pnl
    description: Profit and loss by legal entity and P&L group
    columns:
      - name: pnl_amount_eur
        description: Booked P&L amount in EUR
      - name: bookings
        description: Distinct bookings
```

`adopt('finance')` renders
`EXECUTE SCRIPT SEMANTIC_ADMIN.ADOPT_VIEW('finance', '<this.schema>', '<this.identifier>')`
— plain SQL you could write out by hand. `ADOPT_VIEW` creates the model when it
does not exist (published schema `SEMANTIC_FINANCE`), validates it, publishes
it, and raises on any refusal, which fails the node. The semantic view is named
after the view, upper-cased: `PNL`.

**It follows the view.** Every build adopts again: an unchanged view changes
nothing, and a column removed from it retires its metric. Several views can be
adopted into one model, and dbt's threads may adopt them at once.

**What a view may be.** `SELECT … FROM <one table> [alias] [GROUP BY …]`, with
`SUM`, `COUNT`, `COUNT(DISTINCT …)`, `AVG`, `MIN` and `MAX`, combined freely in
one column (`SUM(a) / NULLIF(SUM(b), 0)` is one metric). Joins belong in the
mart the view reads: join there, adopt a view over the wide table. Anything
else — a join, `WHERE`, `HAVING`, a `GROUP BY` finer than the view's columns —
fails the node with a message naming it. The
[ADOPT_VIEW documentation](https://github.com/exasol-labs/exasol-semantic-views/blob/main/docs/creating-metrics.md#quickest-start-adopt-a-view)
has the full rules.

**Names are per model.** Metric names must be unique across all the views of
one ESV model; two views cannot both have a `revenue` column. Views may share a
dimension — `legal_entity` in two views over the same table — when both select
it the same way.

**Grants are SQL too**, as a second post-hook:

```yaml
      +post-hook:
        - "{{ exasol_semantic_views.adopt('finance') }}"
        - "EXECUTE SCRIPT SEMANTIC_ADMIN.GRANT_MODEL_ROLE('finance', 'FINANCE_ANALYST')"
```

A semantic model over several entities, with relationships between them, is
authored with exasol-semantic-views' scripts and Semantic DDL directly; this
package no longer wraps them (see the [changelog](CHANGELOG.md)).

## Test it

```yaml
models:
  - name: pnl
    data_tests:
      - exasol_semantic_views.validates_clean:   # no ERROR/PRECONDITION issue
          arguments: {model_name: finance}
      - exasol_semantic_views.agent_ready:       # AGENT_READINESS is VALID or WARNING
          arguments: {model_name: finance}
      - exasol_semantic_views.no_retired_views:  # no frozen view retired by a definition change
          arguments: {model_name: finance}
```

`model_name` is the ESV model the view is adopted into, as passed to `adopt()`.
The tests check the whole model, so attaching them to one of its views is enough.

## Query it from a dbt model

```sql
-- models/marts/pnl_by_entity.sql
-- depends_on: {{ ref('pnl') }}
{{ exasol_semantic_views.query(
     model='finance', object='PNL',
     metrics=['pnl_amount_eur', 'bookings'], dimensions=['legal_entity'],
     filters=[{'field': 'pnl_group_name', 'op': '=', 'value': 'Revenue'}],
     order_by=[{'field': 'pnl_amount_eur', 'direction': 'desc'}]) }}
```

The request is compiled at run time with `COMPILE_REQUEST_JSON` and the
governed SQL is inlined, so the model needs no session preprocessor and answers
with the semantic view as adopted in this run. Columns are the requested
fields, upper-cased. The `depends_on` comment is what orders it after the view
model: the compile happens at run time, where dbt's parser cannot see it.

`exasol_semantic_views.compile_sql("SELECT ... FROM SEMANTIC_FINANCE.PNL GROUP BY ...")`
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

then define `exasol__adopt`, `exasol__query`, ... in your project.

## Development

`integration_tests/` is a dbt project that installs this package from `../`,
adopts two view models over a seeded table into one ESV model, queries them
both ways at grains coarser than the views, and checks the answers against the
same numbers computed by hand:

```sh
cd integration_tests
DBT_PROFILES_DIR=. dbt deps
DBT_PROFILES_DIR=. dbt build
```

It needs an Exasol database with exasol-semantic-views installed; set
`EXASOL_DSN`, `EXASOL_USER` and `DBT_ENV_SECRET_EXASOL_PASSWORD`.
