# Interactive billing architecture

Open `http://127.0.0.1:3105/` while the read-only preview is running:

```sh
python3 scripts/architecture_preview.py
```

The standalone [HTML](index.html) also works from disk. It embeds the Savvy
wordmark, fonts, component explanations, captured source excerpts and retained
synthetic engine result. No external JavaScript or CSS library is required.
The existing full application remains at `http://127.0.0.1:3104/`.

## Views

- **Mental model:** pinned inputs and policy → one engine → typed results;
  commercial billing, confirmed cash and supplied accounting stay separate.
- **Components:** complete UI/API, Rails transformation services, PostgreSQL,
  native billing/cash, dbt, mocked CLM/Campfire, and planned worker/storage/agents.
- **Billing engine:** request contract, validation, typed graph interpreter,
  operator composition and all 33 nodes of the retained household calculation.

Click a component to open its implementation, execution contract, current scope
and exact source references. Click a policy node to inspect its actual retained
definition, result and dependencies. Hash URLs deep-link to views and modals.
Escape closes a modal and returns focus to its invoking control. Arrow keys
navigate the three tabs. Print includes all views; Download HTML exports the
self-contained document.

## Source identity

Source links are pinned to prototype commit
`3ce278bb727e333e30b2fcd4eed1be84337b2eeb`.
The local source viewer is restricted to the files listed in `source-map.json`;
it provides current local code with line anchors and SHA-256 hashes. GitHub links
remain pinned to the committed source. Local source links require the preview
server; explanations and captured excerpts remain usable offline.

## Recorded sample

`sample-run.json` is the selected, retained, synthetic `disclosure-run-v1` result
and its policy graph and facts, exported read-only on 18 November 2026. Its
charge is 100,000 USD minor units, allocated 60,000 / 40,000. The page displays
stored values; it does not invoke a billing calculation or issue invoices.
The separately explained $500 credit / $300 refund / $200 remaining balance
comes from the retained disclosure milestone.

## Rebuild and verify

```sh
python3 docs/architecture/build.py
python3 -m py_compile docs/architecture/build.py scripts/architecture_preview.py
```

The builder resolves source anchors from their methods/statements and verifies
source bytes against the pinned commit. To deliberately repin after committing
a source change, use `python3 docs/architecture/build.py --source-commit SHA`.

Browser acceptance uses an existing Playwright installation and local Chrome:

```sh
SAVVY_PLAYWRIGHT_MODULE=/path/to/playwright node scripts/architecture_ui_check.cjs
```

`SAVVY_BROWSER_BINARY` can select an existing Chromium executable. Neither the
preview nor the HTML requires Playwright. No new browser installation or change
to the full application's runtime is required.

18 November validation: **199 checks passed**, including 34 component modals,
33 policy node details, all 30 current source targets, exact line anchors,
keyboard focus and Escape, desktop and 390px layouts, HTML download, offline
operation, print visibility and read-only/source-path boundaries. No browser
runtime or console errors. Local reports and screenshots are ignored under
`.runtime/architecture/`; no retained database reset or provider write occurred.
