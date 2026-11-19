# Interactive billing architecture

Public walkthrough: **https://savvy.beanshop.top/**. The working app is
**https://savvy-proto.beanshop.top/**; both open without sign-in.

The standalone [HTML](index.html) contains the Savvy branding, fonts, explanations,
source excerpts and executed synthetic results. Download HTML from the page for
an offline presentation copy. GitHub links require internet access.

## Three views

- **Mental model:** source records and dated policy assignments feed one engine;
  native billing/earnings, confirmed cash and supplied accounting stay separate.
  Two executed billing subjects connect the model to retained records. The overview
  in the app totals the full book.
- **Components:** UI/API, custom Rails adapter/normalizer and policy services,
  PostgreSQL records, leased ActiveJobs, the worker, native billing/payable/lifecycle
  services, dbt projections and mocked Campfire/CLM. Planned connectors, external
  storage and agents are explicitly identified.
- **Billing engine:** typed policies, frozen inputs, operator composition, result
  allocation and downstream obligations. The retained 33-node household graph is
  a separately labelled minimal example, alongside the fuller product proofs.

Click components for responsibilities, current limits and exact GitHub source.
Hash links open views/modals. Escape returns focus; arrow keys navigate tabs.
Print includes all views. The HTML displays stored results and never prices,
issues documents, moves cash or posts accounting.

## Source and sample identity

`source-map.json` records the exact implementation commit and source file hashes.
`sample-run.json` contains the retained minimal household result;
`lifecycle-run.json` contains the prepared retained preview's two-product native
billing, correction, cash/refund, earnings/payable, accounting and worker evidence.
The current public document commit is in `/build-metadata.json`. Source links may
pin an earlier commit when the linked implementation bytes are unchanged.

## Build and acceptance

```sh
python3 scripts/architecture_preview.py --port 3107
python3 docs/architecture/build.py
python3 scripts/api_contract_check.py
SAVVY_PLAYWRIGHT_MODULE=/path/to/playwright ARCHITECTURE_ORIGIN=http://127.0.0.1:3107 node scripts/architecture_ui_check.cjs
```

Repin deliberately after implementation changes with
`python3 docs/architecture/build.py --source-commit SHA`; the builder verifies
source bytes against that commit. Architecture CI checks reproducible generation,
source paths, all component/node modals, keyboard behavior, desktop/mobile,
offline download, print and read-only boundaries. The release baseline passes
256 architecture checks over 37 components and 33 retained policy nodes.
See [publication operations](../PUBLIC-ARCHITECTURE.md) and the
[four-capability evidence](../FOUR-CAPABILITY-CLOSURE-VALIDATION.md).
