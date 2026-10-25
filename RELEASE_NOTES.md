# pickle_airdrops v1.0.5

## Fixes

- Validate capture identity, proximity, routing bucket and landing/capture timing on the server.
- Check inventory and vehicle reward grants and prevent repeated claims.
- Persist active drops and synchronize players who join late.

## Upgrade notes

- Configure and verify the installed inventory, economy and vehicle ownership adapters.

## Package and validation

- The ZIP contains one pickle_airdrops/ folder with the complete resource, installation files, license and runtime NUI assets where applicable. Unbuilt web/ sources, node_modules/ and Git metadata are excluded.
- Required local NUI scripts and stylesheets were checked before packaging. Prior remediation validation passed targeted mocked regressions and Lua/JavaScript syntax checks; this is not a live FiveM integration test.
- Test the resource with your installed frameworks, inventory, database and other integrations before use. Transactions spanning framework persistence, SQL and local KVP still have crash-recovery boundaries.

Source: [audit remediation PR #3](https://github.com/PickleModsCommunity/pickle_airdrops/pull/3), branch `fix/audit-remediation`. This release includes the PR changes without merging the PR.
