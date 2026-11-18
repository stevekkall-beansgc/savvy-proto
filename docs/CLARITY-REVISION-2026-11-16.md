# Agreement, statement and internal workflow revision

**Update:** Generated sample agreements below are superseded by the real public
disclosures implementation in [the disclosure review](SAVVY-DISCLOSURES-REVIEW-2026-11-16.md).
The current port-3104 LaunchAgent uses `SAVVY_BUILD_DIRECTORY=disclosures` /
`.next-disclosures`; `.next-clarity` is retained for rollback.

16 November 2026. Implements the owner's request for sample agreement PDFs,
invoice-style statement lines, and understandable Product/Finance visualizations
with detail modals. No pricing, recognition treatment or payment execution was added.

## What changed

- Agreements offer a modal with the rendered sample PDF, an original-PDF view link
  and a download link. The two one-page documents use Savvy's logo and colors and
  match the two baseline mock document references/versions. A different or missing
  document reference does not silently open an unrelated sample.
- Each derived statement line has an `invoice_line` mapping: stable line reference,
  line number, description, service-period start/exclusive end, signed amount,
  currency, source result/run and optional quantity/unit-price fields. Quantities
  and prices remain null where no single quantity/price is recorded. The UI shows
  inclusive service dates and opens the calculation/terms/account proof in a modal.
  This is a projection of assessed results, not another invoice or pricing engine.
- Product starts with Activity → Agreement → Calculation → Statement. Each step
  explains its responsibility in a modal. Change, request-review and one-time-item
  actions retain the existing API workflow; full evidence remains reachable.
- Finance separates cash matching from revenue recognition. Receipts, local
  matches and invoices are visually connected, with accounting confirmation shown
  separately. The recognition view has a supplied monthly timeline, independent
  posted outcomes, a separate unbilled-to-billed example and treatment exceptions.
  Raw fields are inside a further technical disclosure rather than the default view.

The existing branding, single interpreter, versioned API policies, exact amounts,
immutable records and scoped reads remain. Campfire/CLM and sample agreements are
mocked. Recognition schedules are supplied facts. The advisor hierarchy stays deferred.

## Validation

- Full guarded Ruby regression: **160 tests / 2,077 assertions**, zero failures,
  errors or skips (`artifacts/medallion/clarity-regression.txt`). The new test checks
  service intervals, exact signed amounts, unique lines and absent invented unit prices.
- Optimized Next.js build and TypeScript pass (`clarity-next-build.txt`,
  `clarity-typecheck.txt`).
- Revised preview: **35 HTTP checks**, including both PDFs and PNG previews,
  media types, proxy origin rejection and exact invoice-shaped line fields.
  Existing three-audience **50 HTTP checks** and **695 medallion assertions** pass.
- Both PDFs were rendered and visually inspected; each is one page. The preview
  images are generated from those actual PDFs, with a direct original-PDF link.
- Browser: PDF modal, download filename/link, Escape dismissal and focus return;
  dated statement table; Product explanation; recognition schedule modal; a real
  local $1 match followed by its linked reversal. The second receipt/invoice
  residuals returned to $200/$100; the original accounting and recognition evidence
  stayed unchanged. Those synthetic acceptance records are retained.
- Mobile at 390px: workflow/detail modal fits without document-level horizontal
  overflow. Wide invoice tables scroll inside their own container. Temporary
  viewport settings were reset; browser warnings/errors were empty.

The design-reference connector required a paid plan. No paid request or upgrade
was made; the revision uses the existing Savvy design system and explicit user feedback.

## Preview and continuity

**Current revision: http://127.0.0.1:3104/**, kept open on Internal Product.
The previous port-3103 preview remains running throughout. Automatic approval
review rejected stopping its LaunchAgent; the revision was built alongside it.
Only the new port-3104 service was briefly stopped for its own final build, with
the original remaining available.

The new user LaunchAgent is `com.beanlabs.savvy-clarity.preview`; its plist is in
`~/Library/LaunchAgents` and its workspace copy/logs are under `.runtime`.
`SAVVY_BUILD_DIRECTORY=clarity` selects `.next-clarity`; the original `.next` build
is untouched. The new proxy accepts only the same bounded loopback API, with
port-3104 origins added to its existing local-origin set. Both use API 3102 and
the retained `savvy-medallion` database. No new infrastructure spend, external
provider call, hosted deployment, GitHub push or release occurred.

To rebuild this revision, keep port 3103 running, stop only the clarity service,
run `SAVVY_BUILD_DIRECTORY=clarity npm --prefix apps/web run build`, then bootstrap
that clarity plist again. Approval requirements still apply to service operations.
Do not build over either live server's build directory.
