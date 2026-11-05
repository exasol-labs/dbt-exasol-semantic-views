# Releasing

1. Run the integration tests against a database with the oldest supported
   exasol-semantic-views release installed (`integration_tests/`, see README).
   CI runs them against that release and against `main` on every push.
2. Date the `CHANGELOG.md` entry (`## X.Y.Z - YYYY-MM-DD`), and set `version:`
   in `dbt_project.yml`.
3. Tag the commit `X.Y.Z` and push the tag. The release workflow checks the tag
   against both files, runs the integration tests, and publishes a GitHub
   release with the CHANGELOG entry as its notes. dbt Hub's hubcap job picks
   new tags up within the hour and opens the listing PR itself.

The first release also needs a one-time PR to
[dbt-labs/hubcap](https://github.com/dbt-labs/hubcap) adding this repository to
`hub.json`, and the repository must be public for hubcap to read it.

Version numbers follow semver; while below 1.0, a breaking change bumps the
minor version. Release tags carry no `v` prefix.
