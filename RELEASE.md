# Releasing

1. Run the integration tests against a database with the oldest supported
   exasol-semantic-views release installed (`integration_tests/`, see README).
2. Move the `CHANGELOG.md` entry out of "unreleased", and set `version:` in
   `dbt_project.yml`.
3. Tag the commit `X.Y.Z` and push the tag. dbt Hub's hubcap job picks new tags
   up within the hour and opens the listing PR itself.

The first release also needs a one-time PR to
[dbt-labs/hubcap](https://github.com/dbt-labs/hubcap) adding this repository to
`hub.json`.

Version numbers follow semver; while below 1.0, a breaking change bumps the
minor version.
