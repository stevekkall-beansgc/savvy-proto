"use client";
import { useEffect, useState } from "react";
import { AgreementDocument } from "./Explain";
type Amount = string | null;
type ValueItem = {
  output_id?: string;
  category?: string;
  basis?: string;
  label: string;
  minor: Amount;
  description?: string;
  basis_rows?: { date: string; minor: Amount; label: string }[];
  status?: string;
};
type Comparison = {
  baseline_label: string;
  baseline_minor: Amount;
  benefits: ValueItem[];
  selected_minor: Amount;
  benefit?: ValueItem | null;
  description?: string;
};
type MedallionRun = {
  id: string;
  status: string;
  period_start: string;
  period_end: string;
  knowledge_cutoff: string;
  summary: ValueItem[];
  detail: ValueItem[];
  comparison: Comparison | null;
  exceptions?: { code: string; message: string }[];
};
type Term = {
  title: string;
  version: string;
  status: string;
  period_start: string;
  period_end: string | null;
  items: { label: string; value: string }[];
  document_ref?: { document_id: string; version: string } | null;
};
type Statement = {
  status: string;
  lines: { label: string; minor: Amount; status: string; reason?: string }[];
  balance_minor: Amount;
  pending_items?: ValueItem[];
};
type Stage = {
  name: string;
  summary: string;
  count: number;
  samples?: Record<string, unknown>[];
};
type Pipeline = {
  stages: Stage[];
  exceptions?: { code: string; message: string }[];
  [key: string]: unknown;
};
export type Data = {
  case_id: string;
  workspace: string;
  run: MedallionRun | null;
  terms: Term[];
  statement: Statement | null;
  pipeline?: Pipeline;
  [key: string]: unknown;
};
function money(v: Amount | undefined) {
  if (v == null) return "Not available";
  const n = BigInt(v),
    a = n < 0n ? -n : n;
  return `${n < 0n ? "−" : ""}$${(a / 100n).toLocaleString("en-US")}.${String(a % 100n).padStart(2, "0")}`;
}
function label(v: string | null | undefined) {
  if (!v) return "Not available";
  return v.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
}
function date(v: string | null | undefined) {
  if (!v) return "Ongoing";
  const [y, m, d] = v.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
function inclusiveEnd(v: string | null | undefined) {
  if (!v) return "Ongoing";
  const [y, m, d] = v.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d - 1)).toLocaleDateString("en-US", {
    timeZone: "UTC",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
function Badge({ children }: { children: React.ReactNode }) {
  return <span className="ws-badge">{children}</span>;
}
function AmountList({
  items,
  external = false,
}: {
  items: ValueItem[];
  external?: boolean;
}) {
  return (
    <div className="md-amount-list">
      {items.map((item, i) => (
        <div className="md-amount-row" key={`${item.label}-${i}`}>
          <div>
            <strong>{item.label}</strong>
            {item.description && <p>{item.description}</p>}
            {item.status &&
              (!external ||
                !["assessed", "completed"].includes(item.status)) && (
                <small>{label(item.status)}</small>
              )}
            {!!item.basis_rows?.length && (
              <details className="md-balance-basis">
                <summary>Daily billable balances</summary>
                <div className="md-balance-scroll">
                  <table aria-label={`${item.label} daily balances`}>
                    <thead><tr><th>Date</th><th>Balance</th></tr></thead>
                    <tbody>{item.basis_rows.map((row, index) => (
                      <tr key={`${row.date}-${index}`}><td>{date(row.date)}</td><td>{money(row.minor)}</td></tr>
                    ))}</tbody>
                  </table>
                </div>
              </details>
            )}
          </div>
          <strong>{money(item.minor)}</strong>
        </div>
      ))}
    </div>
  );
}
function Value({ comparison }: { comparison: Comparison | null }) {
  if (!comparison) return null;
  return (
    <section className="ws-panel md-section">
      <div className="ws-panel-head">
        <div>
          <span className="ws-eyebrow">YOUR TERMS</span>
          <h2>How your terms compare</h2>
          <p>
            {comparison.description ||
              "A comparison using the same activity and period."}
          </p>
        </div>
      </div>
      <div className="md-comparison">
        <div>
          <span>{comparison.baseline_label}</span>
          <strong>{money(comparison.baseline_minor)}</strong>
        </div>
        {comparison.benefits.map((v, i) => (
          <div key={`${v.label}-${i}`}>
            <span>{v.label}</span>
            <strong>{money(v.minor)}</strong>
          </div>
        ))}
        <div className="md-comparison-total">
          <span>With selected terms</span>
          <strong>{money(comparison.selected_minor)}</strong>
        </div>
        {comparison.benefit && (
          <div>
            <span>{comparison.benefit.label}</span>
            <strong>{money(comparison.benefit.minor)}</strong>
          </div>
        )}
      </div>
    </section>
  );
}
function StatementView({ statement }: { statement: Statement | null }) {
  if (!statement)
    return (
      <section className="ws-panel md-section">
        <h2>Statement &amp; payment status</h2>
        <p>Payment status is not available for this period.</p>
      </section>
    );
  return (
    <section className="ws-panel md-section">
      <div className="ws-panel-head">
        <div>
          <h2>Statement &amp; payment status</h2>
        </div>
        <Badge>{label(statement.status)}</Badge>
      </div>
      <AmountList
        external
        items={statement.lines.map((l) => ({
          label: l.label,
          minor: l.minor,
          status: l.status,
          description: l.reason,
        }))}
      />
      <div className="md-statement-total">
        <span>
          {statement.status === "credit_balance"
            ? "Credit balance"
            : "Remaining balance"}
        </span>
        <strong>{money(statement.balance_minor)}</strong>
      </div>
      {statement.status === "credit_balance" && (
        <p className="ws-footnote">
          This credit balance is not evidence of a cash refund.
        </p>
      )}
      {!!statement.pending_items?.length && (
        <details className="md-section">
          <summary>Pending and unapplied activity</summary>
          <p className="ws-footnote">Requests and unapplied payments do not reduce the remaining balance.</p>
          <AmountList external items={statement.pending_items} />
        </details>
      )}
    </section>
  );
}
export function Economics({ data, ria }: { data: Data; ria: boolean }) {
  const run = data.run;
  if (!run)
    return (
      <div className="ws-empty">The selected period is not available yet.</div>
    );
  const [lead, ...other] = run.summary || [];
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">
            {ria ? "YOUR FIRM" : "YOUR COMPENSATION"}
          </span>
          <h1>
            {ria
              ? "Your platform economics."
              : "Your earnings, clearly in view."}
          </h1>
          <p>
            {date(run.period_start)} – {inclusiveEnd(run.period_end)}
          </p>
        </div>
        {run.status !== "completed" && <Badge>{label(run.status)}</Badge>}
      </div>
      {lead && (
        <div className="ws-hero">
          <div>
            <span>{lead.label}</span>
            <strong>{money(lead.minor)}</strong>
            {lead.description && <p>{lead.description}</p>}
            {lead.status &&
              !["assessed", "completed"].includes(lead.status) && (
                <small>{label(lead.status)}</small>
              )}
          </div>
          <div className="ws-hero-side">
            {other.map((x, i) => (
              <div key={`${x.label}-${i}`}>
                <span>{x.label}</span>
                <strong>{money(x.minor)}</strong>
              </div>
            ))}
          </div>
        </div>
      )}
      {(run.exceptions || []).map((e, i) => (
        <div className="ws-warning" key={i}>
          {e.message}
        </div>
      ))}
      {(ria
        ? [
            { category: "charges", title: "Platform charges", description: "" },
            {
              category: "network",
              title: "Network economics",
              description:
                "These account-related allocations are separate from your firm’s platform charges.",
            },
            {
              category: "investor",
              title: "Investor activity",
              description:
                "These amounts belong to investors and are separate from the firm’s bill and credits.",
            },
          ]
        : [
            {
              category: "client_fees",
              title: "Client advisory fees",
              description: "",
            },
            {
              category: "compensation",
              title: "Advisor compensation",
              description: "",
            },
          ]
      ).map((group) => {
        const items = (run.detail || []).filter(
          (x) => x.category === group.category,
        );
        if (!items.length) return null;
        const reported =
          group.category === "network"
            ? items.filter((x) => x.basis === "source_reported")
            : [];
        const primary =
          group.category === "network"
            ? items.filter((x) => x.basis !== "source_reported")
            : items;
        return (
          <section className="ws-panel md-section" key={group.category}>
            <div className="ws-panel-head">
              <div>
                <h2>{group.title}</h2>
                {group.description && <p>{group.description}</p>}
              </div>
            </div>
            <AmountList external items={primary} />
            {reported.length > 0 && (
              <details>
                <summary>Reported allocations</summary>
                <AmountList external items={reported} />
              </details>
            )}
          </section>
        );
      })}
      {(run.detail || []).some(
        (x) =>
          !(
            ria
              ? ["charges", "network", "investor"]
              : ["client_fees", "compensation"]
          ).includes(x.category || ""),
      ) && (
        <section className="ws-panel md-section">
          <div className="ws-panel-head">
            <h2>Other activity</h2>
          </div>
          <AmountList
            external
            items={(run.detail || []).filter(
              (x) =>
                !(
                  ria
                    ? ["charges", "network", "investor"]
                    : ["client_fees", "compensation"]
                ).includes(x.category || ""),
            )}
          />
        </section>
      )}
      <Value comparison={run.comparison} />
      <StatementView statement={data.statement} />
    </>
  );
}
export function Agreements({ terms }: { terms: Term[] }) {
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">YOUR TERMS</span>
          <h1>Agreements &amp; terms.</h1>
          <p>Review the terms used for this period.</p>
        </div>
      </div>
      {terms.length ? (
        terms.map((t, i) => (
          <section className="ws-panel ws-agreement" key={`${t.title}-${i}`}>
            <div className="ws-panel-head">
              <div>
                <h2>{t.title}</h2>
                <p>
                  {date(t.period_start)} – {inclusiveEnd(t.period_end)}
                </p>
              </div>
              <Badge>{label(t.status)}</Badge>
            </div>
            <div className="md-terms">
              {t.items.map((item, j) => (
                <div key={`${item.label}-${j}`}>
                  <span>{item.label}</span>
                  <strong>{item.value}</strong>
                </div>
              ))}
            </div>
            <p className="ws-footnote">
              Agreement reference: {t.document_ref?.document_id || t.version}
              {t.document_ref ? ` · ${t.document_ref.version}` : ""}
            </p>
            <AgreementDocument term={t} />
          </section>
        ))
      ) : (
        <div className="ws-empty">
          Agreement terms are not available for this period.
        </div>
      )}
    </>
  );
}
export function Architecture() {
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL</span>
          <h1>Architecture.</h1>
          <p>How the same policy-driven engine supports both products.</p>
        </div>
      </div>
      <section className="ws-panel md-section">
        <div className="ws-panel-head">
          <h2>From evidence to product</h2>
        </div>
        <div className="md-flow">
          <div>
            <strong>Bronze</strong>
            <span>Original deliveries and event requests</span>
          </div>
          <b>→</b>
          <div>
            <strong>Silver</strong>
            <span>Normalized facts and policy binding</span>
          </div>
          <b>→</b>
          <div>
            <strong>One engine</strong>
            <span>Approved terms and exact calculations</span>
          </div>
          <b>→</b>
          <div>
            <strong>Gold</strong>
            <span>Results, statements and product views</span>
          </div>
        </div>
      </section>
      <section className="ws-panel md-section">
        <h2>Records and responsibilities</h2>
        <div className="md-architecture-table">
          <table>
            <thead><tr><th>Layer</th><th>Record</th><th>Responsibility</th></tr></thead>
            <tbody>
              <tr><th>Bronze</th><td>One original artifact and each delivery</td><td>Keep original bytes, duplicates, rejected arrivals and corrections.</td></tr>
              <tr><th>Silver facts</th><td>One scoped source observation or approved event version</td><td>Normalize balances, account usage, allocations and independent payment evidence.</td></tr>
              <tr><th>Silver terms</th><td>Fact or subject × dated policy/component</td><td>The same engine binds approved assignments and rate versions, retaining its selection reasons.</td></tr>
              <tr><th>Gold detail</th><td>Run × component × parties × economic interval × currency</td><td>Retain exact calculations, assessed amounts and source links; distinguish children from summary outputs.</td></tr>
              <tr><th>Publications</th><td>Selected result × component × hourly or daily refresh</td><td>Publish snapshots. A refresh is separate from daily accrual and billing cadence.</td></tr>
              <tr><th>Savvy billing</th><td>Obligation, invoice/credit or payout instruction and statement version</td><td>Own commercial amounts and approvals. Statements derive from selected results and evidenced applications.</td></tr>
            </tbody>
          </table>
        </div>
      </section>
      <div className="md-info-grid">
        <section className="ws-panel md-section">
          <h2>Authority and handoffs</h2>
          <p>
            Savvy owns policies, billing obligations, invoices and payment
            instructions. Campfire is a mocked accounting handoff; CLM is a
            mocked document and review link. Neither replaces Savvy’s billing
            data. A refresh does not issue a bill, sign a document or move money.
          </p>
        </section>
        <section className="ws-panel md-section">
          <h2>Four distinct clocks</h2>
          <p>
            Service dates determine economics. Knowledge time determines what
            was known. Approval and posting dates govern when changes may enter
            a later statement.
          </p>
        </section>
        <section className="ws-panel md-section">
          <h2>Policy changes</h2>
          <p>
            Rates, eligibility and supported formulas are reviewed versions.
            Both products use the same engine and retain their earlier results.
          </p>
        </section>
        <section className="ws-panel md-section">
          <h2>Capabilities and limits</h2>
          <p>
            Supported policy features are validated before publication.
            Incomplete evidence or unsupported terms block affected results
            instead of creating a guess.
          </p>
        </section>
      </div>
    </>
  );
}
export function PipelineView({
  data,
  busy,
  command,
  scenarioId,
  setScenarioId,
  runId,
  setRunId,
}: {
  data: Data;
  busy: boolean;
  command: Command;
  scenarioId: string;
  setScenarioId: (v: string) => void;
  runId: string;
  setRunId: (v: string) => void;
}) {
  const pipeline = data.pipeline,
    run = data.run;
  const [cutoff, setCutoff] = useState("2026-10-02T23:00:00Z"),
    [policy, setPolicy] = useState("");
  const policies = (data.policies || []) as Json[],
    runs = (data.runs || []) as Json[],
    scenarios = (data.scenarios || [
      { id: "baseline", label: "Baseline" },
    ]) as Json[];
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL</span>
          <h1>Data pipeline.</h1>
          <p>Follow this case from source evidence to the selected result.</p>
        </div>
      </div>
      <section className="ws-panel ws-padded">
        <h2>Choose evidence and run</h2>
        <div className="ws-form-grid">
          <label>
            Scenario
            <select
              value={scenarioId}
              onChange={(e) => {
                setScenarioId(e.target.value);
                setRunId("");
              }}
            >
              {scenarios.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label || s.id}
                </option>
              ))}
            </select>
          </label>
          <label>
            Saved result
            <select value={runId} onChange={(e) => setRunId(e.target.value)}>
              <option value="">Latest result</option>
              {runs.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.knowledge_cutoff} · {label(r.status)}
                </option>
              ))}
            </select>
          </label>
          <label>
            Evidence known by
            <select value={cutoff} onChange={(e) => setCutoff(e.target.value)}>
              {!cutoffs.includes(cutoff) && (
                <option value={cutoff}>Current time · {cutoff}</option>
              )}
              {cutoffs.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="ws-link"
              onClick={() => setCutoff(new Date().toISOString())}
            >
              Use current time
            </button>
          </label>
          <label>
            Published policy
            <select value={policy} onChange={(e) => setPolicy(e.target.value)}>
              <option value="">Choose policy</option>
              {policies
                .filter((p) => p.status === "published")
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.version}
                  </option>
                ))}
            </select>
          </label>
        </div>
        <button
          className="ws-secondary"
          disabled={busy || !policy}
          onClick={async () => {
            const r = (await command("EVALUATE_CASE", {
              case_id: data.case_id,
              scenario_id: scenarioId,
              policy_id: policy,
              knowledge_cutoff: cutoff,
            })) as { id?: string } | null;
            if (r?.id) setRunId(r.id);
          }}
        >
          Evaluate selected evidence
        </button>
      </section>
      {!pipeline ? (
        <div className="ws-empty">
          Pipeline evidence is not available for this case.
        </div>
      ) : (
        <>
          <div className="md-info-grid">
            {pipeline.stages?.map((s) => (
              <section className="ws-panel md-section" key={s.name}>
                <span className="ws-eyebrow">{s.name}</span>
                <h2>{s.count} records</h2>
                <p>{s.summary}</p>
                {s.samples?.length && (
                  <details>
                    <summary>Inspect sample evidence</summary>
                    <pre>{JSON.stringify(s.samples, null, 2)}</pre>
                  </details>
                )}
              </section>
            ))}
          </div>
          {pipeline.exceptions?.map((e, i) => (
            <div className="ws-warning" key={i}>
              {e.message || label(e.code)}
            </div>
          ))}
          {run && (
            <section className="ws-panel md-section">
              <div className="ws-panel-head">
                <h2>Selected results</h2>
                <Badge>{label(run.status)}</Badge>
              </div>
              <AmountList items={run.summary || []} />
              <details>
                <summary>Result details</summary>
                <AmountList items={run.detail || []} />
              </details>
            </section>
          )}
        </>
      )}
    </>
  );
}
type Json = Record<string, any>;
type Command = (
  action: string,
  input: unknown,
  role?: string,
) => Promise<unknown>;
function dateShift(value: string | null | undefined, days: number) {
  if (!value) return "";
  const d = new Date(`${value.slice(0, 10)}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
function ratioPercent(n: number, d: number) {
  const num = BigInt(n) * 1000000n;
  const quotient = num / BigInt(d),
    whole = quotient / 10000n,
    frac = String(quotient % 10000n)
      .padStart(4, "0")
      .replace(/0+$/, "");
  return `${whole}${frac ? `.${frac}` : ""}`;
}
function percentRatio(value: string) {
  if (!/^\d{1,3}(?:\.\d{1,4})?$/.test(value)) return null;
  const [whole, part = ""] = value.split(".");
  const n = BigInt(whole) * 10000n + BigInt(part.padEnd(4, "0"));
  return n <= 1000000n ? { numerator: Number(n), denominator: 1000000 } : null;
}
function inputValue(x: unknown) {
  return x == null ? "" : String(x);
}
export function PolicyEditor({
  data,
  busy,
  command,
}: {
  data: Data;
  busy: boolean;
  command: Command;
}) {
  const policies = (data.policies || []) as Json[];
  const [baseId, setBaseId] = useState(""),
    [version, setVersion] = useState(""),
    [reason, setReason] = useState(""),
    [nodes, setNodes] = useState<Json[]>([]),
    [rates, setRates] = useState<Json[]>([]),
    [selectedRate, setSelectedRate] = useState("");
  const base = policies.find((p) => p.id === baseId);
  useEffect(() => {
    const selected = policies.find((p) => p.id === baseId) || policies[0];
    if (selected) {
      setBaseId(selected.id);
      setVersion(`${selected.policy?.version || selected.version}-draft`);
      setNodes(structuredClone(selected.policy?.nodes || selected.nodes || []));
      setRates(
        (selected.rates || []).map((r: Json) => ({
          ...r,
          numerator: String(r.numerator),
          denominator: String(r.denominator),
          percent: ratioPercent(r.numerator, r.denominator),
          originalPercent: ratioPercent(r.numerator, r.denominator),
          last_day: dateShift(r.ends_on, -1),
        })),
      );
    }
  }, [data.case_id, baseId]);
  const edit = (i: number, key: string, value: unknown) =>
    setNodes((old) =>
      old.map((n, j) => (i === j ? { ...n, [key]: value } : n)),
    );
  const changeOp = (i: number, op: string) =>
    setNodes((old) =>
      old.map((n, j) => {
        if (i !== j) return n;
        const common = Object.fromEntries(
          Object.entries(n).filter(([k]) =>
            [
              "id",
              "role",
              "unit",
              "basis",
              "economic_key",
              "output_class",
              "interval_fact",
              "component",
              "payer",
              "payee",
              "subject",
              "currency",
            ].includes(k),
          ),
        );
        const defaults: Record<string, Json> = {
          literal: { value: "0" },
          fact: { key: "" },
          sum_facts: {
            collection: "",
            selector: {},
            allow_empty: false,
            period: "service",
          },
          add: { inputs: [] },
          min: { inputs: [] },
          max: { inputs: [] },
          subtract: { left: "", right: "" },
          net: { left: "", right: "", authority_fact: "" },
          multiply: { left: "", right: "" },
          accrue: { left: "", right: "" },
          assess: { input: "", rounding: "half_up" },
          bands: { input: "", bands: [] },
          select: { date: "", candidates: [] },
          allocate: { input: "", weights: {}, recipient: "" },
          distribute: { inputs: [], recipient: "" },
        };
        return { ...common, op, ...defaults[op] };
      }),
    );
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL</span>
          <h1>Commercial terms.</h1>
          <p>Create a reviewed policy version from a selected base.</p>
        </div>
      </div>
      <section className="ws-panel ws-padded">
        <div className="ws-panel-head">
          <div>
            <h2>Policy version</h2>
            <p>
              Changes create a draft. Validate through comparison before review
              and publication.
            </p>
          </div>
        </div>
        {!policies.length ? (
          <p className="ws-empty">
            No policy versions are available for this business.
          </p>
        ) : (
          <>
            <div className="ws-form-grid">
              <label>
                Base policy
                <select
                  value={baseId}
                  onChange={(e) => setBaseId(e.target.value)}
                >
                  {policies.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name || p.id} · {label(p.status)}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                New version
                <input
                  value={version}
                  onChange={(e) => setVersion(e.target.value)}
                />
              </label>
              <label>
                Reason
                <input
                  value={reason}
                  maxLength={300}
                  onChange={(e) => setReason(e.target.value)}
                />
              </label>
            </div>
            <section>
              <h3>Negotiated rates</h3>
              <p className="md-help">
                Choose a name, share and dates. A last day is optional. New
                rates must also be referenced by the policy components that use
                them.
              </p>
              <label>Component to change<select value={selectedRate} onChange={(e) => setSelectedRate(e.target.value)}><option value="">Choose a component</option>{rates.map((r) => <option key={r.id} value={r.id}>{r.name || r.component}</option>)}</select></label>
              {rates.map((r, i) => {
                const update = (key: string, value: unknown) =>
                  setRates((old) =>
                    old.map((v, j) => (i === j ? { ...v, [key]: value } : v)),
                  );
                return (
                  <fieldset className="md-node" key={r.id} hidden={selectedRate !== r.id}>
                    <legend>{r.name || "New rate"}</legend>
                    <div className="ws-form-grid">
                      <label>
                        Friendly name
                        <input
                          value={r.name || ""}
                          onChange={(e) => update("name", e.target.value)}
                        />
                      </label>
                      <label>
                        Rate type
                        <select
                          value={r.kind}
                          onChange={(e) => {
                            const kind = e.target.value;
                            setRates((old) =>
                              old.map((v, j) =>
                                i === j
                                  ? {
                                      ...v,
                                      kind,
                                      ...(kind === "targeted_promotion"
                                        ? {}
                                        : {
                                            selector: {},
                                            signup_within_days: null,
                                            priority: null,
                                          }),
                                    }
                                  : v,
                              ),
                            );
                          }}
                        >
                          <option value="standard">Standard</option>
                          <option value="promotion">Broad promotion</option>
                          <option value="targeted_promotion">
                            Targeted promotion
                          </option>
                        </select>
                      </label>
                      <label>
                        Rate (%)
                        <input
                          inputMode="decimal"
                          value={r.percent}
                          onChange={(e) => update("percent", e.target.value)}
                        />
                        {r.originalPercent === r.percent &&
                          (BigInt(r.numerator) * 1000000n) %
                            BigInt(r.denominator) !==
                            0n && (
                            <small>
                              Approximate display; exact rate {r.numerator}/
                              {r.denominator} is retained until edited.
                            </small>
                          )}
                      </label>
                      <label>
                        First day
                        <input
                          type="date"
                          value={r.starts_on || ""}
                          onChange={(e) => update("starts_on", e.target.value)}
                        />
                      </label>
                      <label>
                        Last day (optional)
                        <input
                          type="date"
                          value={r.last_day || ""}
                          onChange={(e) => update("last_day", e.target.value)}
                        />
                      </label>
                      <label>
                        Commercial component
                        <input
                          value={r.component || ""}
                          onChange={(e) => update("component", e.target.value)}
                        />
                      </label>
                      {r.kind === "targeted_promotion" && (
                        <>
                          <label>
                            Customer type (optional)
                            <select
                              value={r.selector?.customer_type || ""}
                              onChange={(e) =>
                                update("selector", {
                                  ...(r.selector || {}),
                                  customer_type: e.target.value || undefined,
                                })
                              }
                            >
                              <option value="">All</option>
                              <option value="new_signup">New signup</option>
                              <option value="individual">Individual</option>
                              <option value="trust">Trust</option>
                              {r.selector?.customer_type &&
                                !["new_signup", "individual", "trust"].includes(
                                  r.selector.customer_type,
                                ) && (
                                  <option value={r.selector.customer_type}>
                                    {label(r.selector.customer_type)}
                                  </option>
                                )}
                            </select>
                          </label>
                          <label>
                            Product type (optional)
                            <select
                              value={r.selector?.product_type || ""}
                              onChange={(e) =>
                                update("selector", {
                                  ...(r.selector || {}),
                                  product_type: e.target.value || undefined,
                                })
                              }
                            >
                              <option value="">All</option>
                              <option value="managed">Managed</option>
                              <option value="planning">Planning</option>
                              {r.selector?.product_type &&
                                !["managed", "planning"].includes(
                                  r.selector.product_type,
                                ) && (
                                  <option value={r.selector.product_type}>
                                    {label(r.selector.product_type)}
                                  </option>
                                )}
                            </select>
                          </label>
                          <label>
                            Within days of signup (optional)
                            <input
                              inputMode="numeric"
                              value={r.signup_within_days ?? ""}
                              onChange={(e) =>
                                update("signup_within_days", e.target.value)
                              }
                            />
                          </label>
                          <label>
                            Priority (optional)
                            <input
                              inputMode="numeric"
                              value={r.priority ?? ""}
                              onChange={(e) =>
                                update("priority", e.target.value)
                              }
                            />
                          </label>
                        </>
                      )}
                    </div>
                    <details>
                      <summary>Rate reference and direction</summary>
                      <small>
                        {r.id} · {r.broker_id} ·{" "}
                        {r.payer_id || "Unspecified payer"} →{" "}
                        {r.payee_id || "Unspecified payee"}
                      </small>
                    </details>
                  </fieldset>
                );
              })}
              <button
                className="ws-secondary"
                onClick={() => {
                  const sample = rates[0];
                  setRates((old) => [
                    ...old,
                    {
                      id: `rate-${crypto.randomUUID()}`,
                      name: "",
                      kind: "targeted_promotion",
                      percent: "",
                      originalPercent: null,
                      numerator: "0",
                      denominator: "1",
                      starts_on: "2026-09-01",
                      last_day: "",
                      selector: {},
                      component: sample?.component || "advisor_share",
                      broker_id:
                        sample?.broker_id ||
                        (data.case_id === "advisor"
                          ? "advisor-demo"
                          : "ria-harbor"),
                      payer_id: sample?.payer_id || null,
                      payee_id: sample?.payee_id || null,
                      commercial_group: sample?.commercial_group || null,
                    },
                  ]);
                }}
              >
                + Add rate
              </button>
            </section>
            <details className="aud-advanced"><summary>Advanced policy components</summary>
            <p className="md-help">
              Each component uses a supported operation and refers to named
              inputs. Amounts and ratios are exact values; the engine validates
              units, dependencies and scope.
            </p>
            {nodes.map((n, i) => (
              <details className="md-node" key={`${n.id}-${i}`}>
                <summary>
                  <strong>{n.name || n.id || "New component"}</strong>
                  <span>
                    {label(n.op)} · {label(n.role)}
                  </span>
                </summary>
                <div className="ws-form-grid">
                  {(
                    [
                      ["id", "Component ID"],
                      ["op", "Operation"],
                      ["role", "Output role"],
                      ["unit", "Unit"],
                      ["basis", "Basis"],
                    ] as const
                  ).map(([key, title]) => (
                    <label key={key}>
                      {title}
                      {key === "op" ? (
                        <select
                          value={inputValue(n[key])}
                          onChange={(e) => changeOp(i, e.target.value)}
                        >
                          {[
                            "literal",
                            "fact",
                            "sum_facts",
                            "add",
                            "subtract",
                            "net",
                            "multiply",
                            "accrue",
                            "distribute",
                            "min",
                            "max",
                            "assess",
                            "bands",
                            "select",
                            "allocate",
                          ].map((v) => (
                            <option key={v} value={v}>
                              {label(v)}
                            </option>
                          ))}
                        </select>
                      ) : key === "role" ? (
                        <select
                          value={inputValue(n[key])}
                          onChange={(e) => edit(i, key, e.target.value)}
                        >
                          {["intermediate", "terminal", "summary"].map((v) => (
                            <option key={v}>{v}</option>
                          ))}
                        </select>
                      ) : key === "basis" ? (
                        <select
                          value={inputValue(n[key])}
                          onChange={(e) => edit(i, key, e.target.value)}
                        >
                          {[
                            "scalar",
                            "exact_accrual",
                            "assessed",
                            "source_reported",
                          ].map((v) => (
                            <option key={v}>{v}</option>
                          ))}
                        </select>
                      ) : (
                        <input
                          value={inputValue(n[key])}
                          onChange={(e) => edit(i, key, e.target.value)}
                        />
                      )}
                    </label>
                  ))}
                  {["terminal", "summary"].includes(n.role) && (
                    <label>
                      Output classification
                      <select
                        value={inputValue(n.output_class)}
                        onChange={(e) =>
                          edit(i, "output_class", e.target.value)
                        }
                      >
                        <option value="">Choose classification</option>
                        <option value="metric">Metric</option>
                        <option value="comparison">Comparison</option>
                        <option value="evidence">Evidence</option>
                        <option value="obligation">Obligation</option>
                        <option value="net_balance">Net balance</option>
                      </select>
                    </label>
                  )}
                  {[
                    "component",
                    "economic_key",
                    "currency",
                    "interval_fact",
                  ].map((k) => (
                    <label key={k}>
                      {label(k)}
                      <input
                        value={inputValue(n[k])}
                        onChange={(e) =>
                          edit(i, k, e.target.value || undefined)
                        }
                      />
                    </label>
                  ))}
                  {["payer", "payee", "subject"].map((k) => (
                    <label key={k}>
                      {label(k)}
                      <select
                        value={inputValue(n[k])}
                        onChange={(e) =>
                          edit(i, k, e.target.value || undefined)
                        }
                      >
                        <option value="">Not specified</option>
                        {(
                          ((k === "subject" ? data.subjects : data.parties) ||
                            []) as Json[]
                        ).map((p: Json) => (
                          <option key={p.id} value={p.id}>
                            {p.name}
                          </option>
                        ))}
                        {k !== "subject" && (
                          <option value="client">Client</option>
                        )}
                        {n[k] &&
                          ![
                            ...((data.parties || []) as Json[]),
                            ...((data.subjects || []) as Json[]),
                          ].some((p: Json) => p.id === n[k]) &&
                          n[k] !== "client" && (
                            <option value={n[k]}>{n[k]}</option>
                          )}
                      </select>
                    </label>
                  ))}
                  {n.op === "literal" && (
                    <label>
                      Exact value (integer or fraction)
                      <input
                        value={inputValue(n.value)}
                        onChange={(e) => edit(i, "value", e.target.value)}
                      />
                    </label>
                  )}
                  {n.op === "sum_facts" && (
                    <>
                      <label>
                        Source collection
                        <input
                          value={inputValue(n.collection)}
                          onChange={(e) =>
                            edit(i, "collection", e.target.value)
                          }
                        />
                      </label>
                      <label>
                        Period
                        <select
                          value={inputValue(n.period)}
                          onChange={(e) => edit(i, "period", e.target.value)}
                        >
                          <option value="service">Service period</option>
                          <option value="all">All eligible dates</option>
                        </select>
                      </label>
                      <label>
                        When no facts match
                        <select
                          value={String(n.allow_empty)}
                          onChange={(e) =>
                            edit(i, "allow_empty", e.target.value === "true")
                          }
                        >
                          <option value="false">Block result</option>
                          <option value="true">
                            Use zero for an empty eligible collection
                          </option>
                        </select>
                      </label>
                    </>
                  )}
                  {n.op === "fact" && (
                    <label>
                      Source fact key
                      <input
                        value={inputValue(n.key)}
                        onChange={(e) => edit(i, "key", e.target.value)}
                      />
                    </label>
                  )}
                  {["add", "min", "max", "distribute"].includes(n.op) && (
                    <div>
                      <strong>Input components</strong>
                      {(n.inputs || []).map((value: string, j: number) => (
                        <label key={j}>
                          Input {j + 1}
                          <input
                            value={value}
                            onChange={(e) =>
                              edit(
                                i,
                                "inputs",
                                n.inputs.map((v: string, k: number) =>
                                  j === k ? e.target.value : v,
                                ),
                              )
                            }
                          />
                          <button
                            className="ws-link"
                            type="button"
                            onClick={() =>
                              edit(
                                i,
                                "inputs",
                                n.inputs.filter(
                                  (_: string, k: number) => k !== j,
                                ),
                              )
                            }
                          >
                            Remove input
                          </button>
                        </label>
                      ))}
                      <button
                        className="ws-secondary"
                        type="button"
                        onClick={() =>
                          edit(i, "inputs", [...(n.inputs || []), ""])
                        }
                      >
                        Add input
                      </button>
                    </div>
                  )}
                  {["multiply", "subtract", "net", "accrue"].includes(n.op) && (
                    <>
                      <label>
                        Left component
                        <input
                          value={inputValue(n.left)}
                          onChange={(e) => edit(i, "left", e.target.value)}
                        />
                      </label>
                      <label>
                        Right component
                        <input
                          value={inputValue(n.right)}
                          onChange={(e) => edit(i, "right", e.target.value)}
                        />
                      </label>
                    </>
                  )}
                  {["assess", "bands", "allocate"].includes(n.op) && (
                    <label>
                      Input component
                      <input
                        value={inputValue(n.input)}
                        onChange={(e) => edit(i, "input", e.target.value)}
                      />
                    </label>
                  )}
                  {n.op === "net" && (
                    <label>
                      Netting authority fact
                      <input
                        value={inputValue(n.authority_fact)}
                        onChange={(e) =>
                          edit(i, "authority_fact", e.target.value)
                        }
                      />
                    </label>
                  )}
                  {n.op === "distribute" && (
                    <label>
                      Recipient component
                      <input
                        value={inputValue(n.recipient)}
                        onChange={(e) => edit(i, "recipient", e.target.value)}
                      />
                    </label>
                  )}
                  {n.op === "select" && (
                    <label>
                      Selection date fact (optional)
                      <input
                        value={inputValue(n.date_fact)}
                        onChange={(e) =>
                          setNodes((old) =>
                            old.map((node, j) => {
                              if (j !== i) return node;
                              const next: Json = { ...node };
                              if (e.target.value) {
                                delete next.date;
                                next.date_fact = e.target.value;
                              } else {
                                delete next.date_fact;
                                next.date = "";
                              }
                              return next;
                            }),
                          )
                        }
                      />
                    </label>
                  )}
                  {n.op === "assess" && (
                    <label>
                      Rounding
                      <select
                        value={inputValue(n.rounding)}
                        onChange={(e) => edit(i, "rounding", e.target.value)}
                      >
                        <option value="half_up">Half up</option>
                      </select>
                    </label>
                  )}
                  {n.op === "select" && (
                    <label>
                      Selection date
                      <input
                        type="date"
                        value={inputValue(n.date)}
                        onChange={(e) =>
                          setNodes((old) =>
                            old.map((node, j) => {
                              if (j !== i) return node;
                              const next: Json = {
                                ...node,
                                date: e.target.value,
                              };
                              delete next.date_fact;
                              return next;
                            }),
                          )
                        }
                      />
                    </label>
                  )}
                </div>
                {(n.op === "fact" || n.op === "sum_facts") && (
                  <PredicateEditor
                    title={
                      n.op === "fact"
                        ? "Required evidence"
                        : "Eligible fact conditions"
                    }
                    values={
                      n.op === "fact" ? n.requires || {} : n.selector || {}
                    }
                    onChange={(v) =>
                      edit(i, n.op === "fact" ? "requires" : "selector", v)
                    }
                  />
                )}
                {n.op === "bands" && (
                  <div>
                    <strong>Marginal bands</strong>
                    {(n.bands || []).map((band: Json, j: number) => (
                      <div className="ws-form-grid" key={j}>
                        <label>
                          Upper bound (empty means no limit)
                          <input
                            value={inputValue(band.upper)}
                            onChange={(e) =>
                              edit(
                                i,
                                "bands",
                                n.bands.map((v: Json, k: number) =>
                                  k === j
                                    ? { ...v, upper: e.target.value || null }
                                    : v,
                                ),
                              )
                            }
                          />
                        </label>
                        <label>
                          Rate component
                          <input
                            value={inputValue(band.rate)}
                            onChange={(e) =>
                              edit(
                                i,
                                "bands",
                                n.bands.map((v: Json, k: number) =>
                                  k === j ? { ...v, rate: e.target.value } : v,
                                ),
                              )
                            }
                          />
                        </label>
                      </div>
                    ))}
                    <button
                      className="ws-secondary"
                      onClick={() =>
                        edit(i, "bands", [
                          ...(n.bands || []),
                          { upper: null, rate: "" },
                        ])
                      }
                    >
                      Add band
                    </button>
                  </div>
                )}
                {n.op === "allocate" && (
                  <div>
                    <label>
                      Recipient
                      <input
                        value={inputValue(n.recipient)}
                        onChange={(e) => edit(i, "recipient", e.target.value)}
                      />
                    </label>
                    <strong>Allocation weights (exact fractions)</strong>
                    {Object.entries(n.weights || {}).map(([party, weight]) => (
                      <div className="ws-form-grid" key={party}>
                        <label>
                          Party
                          <input
                            value={party}
                            onChange={(e) => {
                              const weights = { ...n.weights };
                              delete weights[party];
                              weights[e.target.value] = weight;
                              edit(i, "weights", weights);
                            }}
                          />
                        </label>
                        <label>
                          Weight
                          <input
                            value={inputValue(weight)}
                            onChange={(e) =>
                              edit(i, "weights", {
                                ...n.weights,
                                [party]: e.target.value,
                              })
                            }
                          />
                        </label>
                        <button
                          className="ws-link"
                          onClick={() => {
                            const weights = { ...n.weights };
                            delete weights[party];
                            edit(i, "weights", weights);
                          }}
                        >
                          Remove weight
                        </button>
                      </div>
                    ))}
                    <button
                      className="ws-secondary"
                      onClick={() =>
                        edit(i, "weights", {
                          ...(n.weights || {}),
                          [`party-${Object.keys(n.weights || {}).length + 1}`]:
                            "0",
                        })
                      }
                    >
                      Add weight
                    </button>
                  </div>
                )}
                {n.op === "select" && (
                  <div>
                    <strong>Eligibility choices</strong>
                    {(n.candidates || []).map((c: Json, j: number) => (
                      <div className="md-choice" key={j}>
                        <div className="ws-form-grid">
                          {(
                            [
                              "id",
                              "value",
                              "from",
                              "to",
                              "priority",
                              "signup_fact",
                              "days",
                            ] as const
                          ).map((k) => (
                            <label key={k}>
                              {label(k)}
                              <input
                                type={
                                  ["from", "to"].includes(k) ? "date" : "text"
                                }
                                value={inputValue(c[k])}
                                onChange={(e) =>
                                  edit(
                                    i,
                                    "candidates",
                                    n.candidates.map((v: Json, k2: number) =>
                                      k2 === j
                                        ? {
                                            ...v,
                                            [k]:
                                              ["priority", "days"].includes(
                                                k,
                                              ) && e.target.value
                                                ? Number(e.target.value)
                                                : e.target.value || null,
                                          }
                                        : v,
                                    ),
                                  )
                                }
                              />
                            </label>
                          ))}
                        </div>
                        <div>
                          <strong>Required fact matches</strong>
                          {Object.entries(c.matches || {}).map(
                            ([key, value]) => (
                              <div className="ws-form-grid" key={key}>
                                <label>
                                  Fact key
                                  <input
                                    value={key}
                                    onChange={(e) => {
                                      const matches = { ...c.matches };
                                      delete matches[key];
                                      matches[e.target.value] = value;
                                      edit(
                                        i,
                                        "candidates",
                                        n.candidates.map(
                                          (v: Json, k: number) =>
                                            j === k ? { ...v, matches } : v,
                                        ),
                                      );
                                    }}
                                  />
                                </label>
                                <label>
                                  Expected value
                                  <input
                                    value={inputValue(value)}
                                    onChange={(e) =>
                                      edit(
                                        i,
                                        "candidates",
                                        n.candidates.map(
                                          (v: Json, k: number) =>
                                            j === k
                                              ? {
                                                  ...v,
                                                  matches: {
                                                    ...c.matches,
                                                    [key]: e.target.value,
                                                  },
                                                }
                                              : v,
                                        ),
                                      )
                                    }
                                  />
                                </label>
                                <button
                                  className="ws-link"
                                  onClick={() => {
                                    const matches = { ...c.matches };
                                    delete matches[key];
                                    edit(
                                      i,
                                      "candidates",
                                      n.candidates.map((v: Json, k: number) =>
                                        j === k ? { ...v, matches } : v,
                                      ),
                                    );
                                  }}
                                >
                                  Remove condition
                                </button>
                              </div>
                            ),
                          )}
                          <button
                            className="ws-secondary"
                            onClick={() =>
                              edit(
                                i,
                                "candidates",
                                n.candidates.map((v: Json, k: number) =>
                                  j === k
                                    ? {
                                        ...v,
                                        matches: {
                                          ...(c.matches || {}),
                                          [`fact-${Object.keys(c.matches || {}).length + 1}`]:
                                            "",
                                        },
                                      }
                                    : v,
                                ),
                              )
                            }
                          >
                            Add condition
                          </button>
                        </div>
                        <button
                          className="ws-link"
                          onClick={() =>
                            edit(
                              i,
                              "candidates",
                              n.candidates.filter(
                                (_: Json, k: number) => k !== j,
                              ),
                            )
                          }
                        >
                          Remove choice
                        </button>
                      </div>
                    ))}
                    <button
                      className="ws-secondary"
                      onClick={() =>
                        edit(i, "candidates", [
                          ...(n.candidates || []),
                          { id: "", value: "", priority: 0, matches: {} },
                        ])
                      }
                    >
                      Add choice
                    </button>
                  </div>
                )}
                <button
                  className="ws-link"
                  onClick={() =>
                    setNodes((old) => old.filter((_, j) => i !== j))
                  }
                >
                  Remove component
                </button>
              </details>
            ))}
            <button
              className="ws-secondary"
              onClick={() =>
                setNodes((old) => [
                  ...old,
                  {
                    id: "",
                    op: "literal",
                    role: "intermediate",
                    unit: "scalar",
                    basis: "scalar",
                    value: "0",
                  },
                ])
              }
            >
              + Add component
            </button>
            </details>
            <div className="ws-form-footer">
              <p>Saved changes do not affect published results.</p>
              <button
                className="ws-primary"
                disabled={
                  busy ||
                  !base ||
                  !version.trim() ||
                  reason.trim().length < 3 ||
                  rates.some(
                    (r) =>
                      !r.name?.trim() ||
                      !r.starts_on ||
                      !r.component ||
                      ((!r.originalPercent ||
                        r.percent !== r.originalPercent) &&
                        percentRatio(r.percent) === null) ||
                      (r.last_day && r.last_day < r.starts_on) ||
                      (r.signup_within_days &&
                        (!/^\d+$/.test(String(r.signup_within_days)) ||
                          Number(r.signup_within_days) < 1 ||
                          Number(r.signup_within_days) > 365)) ||
                      (r.priority && !/^-?\d+$/.test(String(r.priority))),
                  )
                }
                onClick={() =>
                  base &&
                  command("SAVE_POLICY_VERSION", {
                    case_id: data.case_id,
                    base_id: base.id,
                    expected_base_hash: base.hash,
                    policy: { ...base.policy, version: version.trim(), nodes },
                    rates: rates.map((r) => {
                      const ratio =
                        r.percent === r.originalPercent
                          ? {
                              numerator: Number(r.numerator),
                              denominator: Number(r.denominator),
                            }
                          : percentRatio(r.percent)!;
                      return {
                        id: r.id,
                        name: r.name.trim(),
                        kind: r.kind,
                        ...ratio,
                        starts_on: r.starts_on,
                        ends_on: r.last_day ? dateShift(r.last_day, 1) : null,
                        selector: Object.fromEntries(
                          Object.entries(r.selector || {}).filter(([, v]) => v),
                        ),
                        signup_within_days: r.signup_within_days
                          ? Number(r.signup_within_days)
                          : null,
                        priority:
                          r.priority !== "" && r.priority != null
                            ? Number(r.priority)
                            : null,
                        component: r.component,
                        broker_id: r.broker_id,
                        payer_id: r.payer_id || null,
                        payee_id: r.payee_id || null,
                        commercial_group: r.commercial_group || null,
                      };
                    }),
                    reason: reason.trim(),
                  })
                }
              >
                Save draft
              </button>
            </div>
          </>
        )}
      </section>
    </>
  );
}
const cutoffs = [
  "2026-10-01T23:00:00Z",
  "2026-10-02T23:00:00Z",
  "2026-10-03T23:00:00Z",
];
export function PolicyApprovals({
  data,
  busy,
  command,
  requestPolicy,
}: {
  data: Data;
  busy: boolean;
  command: Command;
  requestPolicy?: Json;
}) {
  const policies = (data.policies || []) as Json[],
    comparisons = (data.comparisons || []) as Json[],
    reviews = (data.reviews || []) as Json[];
  const [base, setBase] = useState(requestPolicy?.base_id || ""),
    [proposed, setProposed] = useState(requestPolicy?.id || ""),
    [cutoff, setCutoff] = useState(cutoffs[1]),
    [documentId, setDocumentId] = useState("mock-policy-review"),
    [version, setVersion] = useState("v1"),
    [effectiveFrom, setEffectiveFrom] = useState("2026-10-03");
  return (
    <>
      {!requestPolicy && <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL</span>
          <h1>Approvals.</h1>
          <p>
            Compare the same inputs, then bind mock reviews to the exact version
            and document.
          </p>
        </div>
      </div>}
      <section className="ws-panel ws-padded">
        <h2>{requestPolicy ? "Impact on the same activity" : "Compare policy versions"}</h2>
        {requestPolicy && <p>Baseline: {policies.find(p => p.id === base)?.version || "Published base"} · Proposed: {requestPolicy.version}</p>}
        <div className="ws-form-grid">
          {!requestPolicy && <label>
            Baseline
            <select value={base} onChange={(e) => setBase(e.target.value)}>
              <option value="">Choose policy</option>
              {policies.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.version} · {label(p.status)}
                </option>
              ))}
            </select>
          </label>}
          {!requestPolicy && <label>
            Proposed
            <select
              value={proposed}
              onChange={(e) => setProposed(e.target.value)}
            >
              <option value="">Choose policy</option>
              {policies.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.version} · {label(p.status)}
                </option>
              ))}
            </select>
          </label>}
          <label>
            Evidence known by
            <select value={cutoff} onChange={(e) => setCutoff(e.target.value)}>
              {!cutoffs.includes(cutoff) && (
                <option value={cutoff}>Current time · {cutoff}</option>
              )}
              {cutoffs.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="ws-link"
              onClick={() => setCutoff(new Date().toISOString())}
            >
              Use current time
            </button>
          </label>
        </div>
        <button
          className="ws-secondary"
          disabled={busy || !base || !proposed}
          onClick={() =>
            command("COMPARE_POLICIES", {
              case_id: data.case_id,
              baseline_policy_id: base,
              proposed_policy_id: proposed,
              knowledge_cutoff: cutoff,
            })
          }
        >
          {requestPolicy ? "Calculate impact" : "Compare policies"}
        </button>
      </section>
      {(requestPolicy ? comparisons.filter(c => c.proposed_policy_id === proposed && c.baseline_policy_id === base).slice(-1) : comparisons).map((c) => {
        const matching = reviews.filter(
          (r) =>
            r.policy_id === c.proposed_policy_id &&
            r.comparison_id === c.id &&
            r.document_ref?.document_id === documentId &&
            r.document_ref?.version === version &&
            r.decision === "approved_for_demo",
        );
        const approved = (r: string) => matching.some((x) => x.role === r);
        return (
          <section className="ws-panel ws-padded" key={c.id}>
            <div className="ws-panel-head">
              <div>
                <h2>Comparison</h2>
                <p>
                  Known by {c.knowledge_cutoff} · {c.baseline_policy_id} →{" "}
                  {c.proposed_policy_id}
                </p>
              </div>
            </div>
            {requestPolicy ? <><ImpactSummary result={c} caseId={data.case_id}/><details className="aud-advanced"><summary>Full comparison evidence</summary><ComparisonDetails result={c}/></details></> : <ComparisonDetails result={c} />}
            <div className="ws-form-grid">
              <label>
                Mock document ID
                <input
                  value={documentId}
                  onChange={(e) => setDocumentId(e.target.value)}
                />
              </label>
              <label>
                Effective from
                <input
                  type="date"
                  value={effectiveFrom}
                  onChange={(e) => setEffectiveFrom(e.target.value)}
                />
              </label>
              <label>
                Mock document version
                <input
                  value={version}
                  onChange={(e) => setVersion(e.target.value)}
                />
              </label>
            </div>
            <div className="ws-review-actions">
              {["legal", "finance"].map((role) => (
                <div key={role}>
                  <strong>{label(role)}</strong>
                  <span>
                    {approved(role)
                      ? "Reviewed for this comparison"
                      : "Review needed"}
                  </span>
                  <button
                    className="ws-secondary"
                    disabled={
                      busy ||
                      c.status !== "completed" ||
                      !documentId ||
                      !version ||
                      approved(role)
                    }
                    onClick={() =>
                      command(
                        "REVIEW_POLICY",
                        {
                          case_id: data.case_id,
                          policy_id: c.proposed_policy_id,
                          comparison_id: c.id,
                          document_ref: {
                            system: "mock_clm",
                            document_id: documentId,
                            version,
                            status: "reviewed_for_demo",
                          },
                          decision: "approved_for_demo",
                        },
                        role,
                      )
                    }
                  >
                    Simulate {label(role)} review
                  </button>
                </div>
              ))}
            </div>
            <details className="aud-advanced"><summary>Publish reviewed terms</summary><p>Publication is an explicit step after both reviews. Assignment is separate.</p><button
              className="ws-primary"
              disabled={
                busy ||
                c.status !== "completed" ||
                !effectiveFrom ||
                !approved("legal") ||
                !approved("finance")
              }
              onClick={() =>
                command(
                  "PUBLISH_POLICY",
                  {
                    case_id: data.case_id,
                    policy_id: c.proposed_policy_id,
                    comparison_id: c.id,
                    effective_from: effectiveFrom,
                  },
                  "finance",
                )
              }
            >
              Publish reviewed policy
            </button></details>
            <p className="ws-footnote">
              Mock review only. No document is signed or sent.
            </p>
          </section>
        );
      })}
      <details className="aud-advanced"><summary>Assign published terms</summary><PolicyAssignment data={data} busy={busy} command={command} /></details>
    </>
  );
}
function ImpactSummary({result,caseId}: {result:Json;caseId:string}) {
 const monetary=(side:Json)=>Object.fromEntries((side?.details || []).filter((d:Json)=>["terminal","summary"].includes(d.role) && d.unit==="USD_minor").map((d:Json)=>[d.id,d]));
 const before=monetary(result.baseline),after=monetary(result.proposed),headline=caseId==="advisor"?"payable":"net";
 const keys=Array.from(new Set([...Object.keys(before),...Object.keys(after)])).filter(id=>id===headline || (caseId==="advisor" && id==="compensation") || String(before[id]?.assessed_minor ?? "")!==String(after[id]?.assessed_minor ?? ""));
 return <div><p>Both versions use the same recorded inputs. An unchanged headline can include offsetting component changes.</p>{result.status!=="completed" && <p className="ws-warning">This impact is blocked and cannot be reviewed.</p>}{keys.length ? <div className="aud-rows">{keys.map(id=><div className="aud-row" key={id}><strong>{id===headline ? (caseId==="advisor"?"Amount due to advisor":"Firm net amount") : ({share_total:"Fee-share compensation",topup:"Guarantee top-up",compensation:"Total compensation",bonus:"Bonus"} as Record<string,string>)[id] || label(id)}</strong><span>{money(before[id]?.assessed_minor == null ? null : String(before[id].assessed_minor))} → {money(after[id]?.assessed_minor == null ? null : String(after[id].assessed_minor))}</span></div>)}</div>:<p>No assessed differences are available.</p>}</div>;
}

function ComparisonDetails({ result }: { result: Json }) {
  const rows = (value: Json) =>
    (value?.details || [])
      .filter(
        (d: Json) =>
          ["terminal", "summary"].includes(d.role) && d.unit === "USD_minor",
      )
      .map((d: Json) => ({
        label: label(d.id),
        minor: d.assessed_minor == null ? null : String(d.assessed_minor),
      }));
  return (
    <div className="md-info-grid">
      <section>
        <h3>Baseline</h3>
        <AmountList items={rows(result.baseline)} />
      </section>
      <section>
        <h3>Proposed</h3>
        <AmountList items={rows(result.proposed)} />
      </section>
      {result.status !== "completed" && (
        <p className="ws-warning">
          This comparison is blocked and cannot be reviewed.
        </p>
      )}
      <details>
        <summary>Comparison evidence</summary>
        <pre>{JSON.stringify(result, null, 2)}</pre>
      </details>
    </div>
  );
}
function dollarsToCents(value: string) {
  if (!/^\d{1,13}(?:\.\d{1,2})?$/.test(value)) return null;
  const [whole, fraction = ""] = value.split(".");
  return (BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"))).toString();
}
export function Adjustments({
  data,
  busy,
  command,
}: {
  data: Data;
  busy: boolean;
  command: Command;
}) {
  const events = (data.events || []) as Json[],
    policies = (data.policies || []) as Json[],
    eventPolicies = (data.event_policies || []) as Json[],
    parties = (data.parties || []) as { id: string; name: string }[],
    subjects = (data.subjects || data.parties || []) as {
      id: string;
      name: string;
    }[];
  const [kind, setKind] = useState(""),
    [amount, setAmount] = useState(""),
    [debtor, setDebtor] = useState(""),
    [creditor, setCreditor] = useState(""),
    [subject, setSubject] = useState(""),
    [reason, setReason] = useState(""),
    [economicDate, setEconomicDate] = useState("2026-09-30"),
    [posting, setPosting] = useState("2026-10"),
    [policy, setPolicy] = useState(""),
    [eventPolicy, setEventPolicy] = useState(""),
    [original, setOriginal] = useState("");
  const minor = dollarsToCents(amount);
  useEffect(() => {
    if (!kind) return;
    const business = data.case_id === "ria" ? "ria-harbor" : "advisor-demo";
    const credit = kind === "one_time_credit" || data.case_id === "advisor";
    setDebtor(credit ? "firm-demo" : business);
    setCreditor(credit ? business : "firm-demo");
    setSubject(business);
    setPolicy(policies.find((p) => p.status === "published")?.id || "");
  }, [kind, data.case_id]);
  useEffect(() => {
    setEventPolicy(eventPolicies.find((r: Json) => r.policy_id === policy && r.kind === kind)?.id || "");
  }, [policy, kind, data.case_id]);
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL</span>
          <h1>Adjustments.</h1>
          <p>
            Request and review economic events separately from payment evidence.
          </p>
        </div>
      </div>
      <section className="ws-panel ws-padded">
        <h2>Request a one-time item</h2>
        <div className="ws-form-grid">
          <label>
            Purpose
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="">Choose type</option>
              {data.case_id === "ria" ? (
                <>
                  <option value="one_time_charge">One-time charge</option>
                  <option value="one_time_credit">Service credit</option>
                </>
              ) : (
                <>
                  <option value="compensation_entitlement">
                    Compensation entitlement
                  </option>
                  <option value="payout_request">Payout request</option>
                </>
              )}
            </select>
          </label>
          <label>
            Amount (USD)
            <input
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
            />
          </label>
          <label>
            Owed by
            <select value={debtor} onChange={(e) => setDebtor(e.target.value)}>
              <option value="">Choose party</option>
              {parties.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Owed to
            <select
              value={creditor}
              onChange={(e) => setCreditor(e.target.value)}
            >
              <option value="">Choose party</option>
              {parties.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Business
            <select
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
            >
              <option value="">Choose subject</option>
              {subjects.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Service date
            <input
              type="date"
              value={economicDate}
              onChange={(e) => setEconomicDate(e.target.value)}
            />
          </label>
          <label>
            Posting period
            <input
              type="month"
              value={posting}
              onChange={(e) => setPosting(e.target.value)}
            />
          </label>
          <label>
            Published terms
            <select value={policy} onChange={(e) => setPolicy(e.target.value)}>
              <option value="">Choose policy</option>
              {policies
                .filter((p) => p.status === "published")
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.version}
                  </option>
                ))}
            </select>
          </label>
          {kind !== "payout_request" && (
            <label>
              Applicable treatment
              <select
                value={eventPolicy}
                onChange={(e) => setEventPolicy(e.target.value)}
              >
                <option value="">Choose approved treatment</option>
                {eventPolicies
                  .filter(
                    (r: Json) => r.policy_id === policy && r.kind === kind,
                  )
                  .map((r: Json) => (
                    <option key={r.id} value={r.id}>
                      {label(r.kind)} · {label(r.group)}
                    </option>
                  ))}
              </select>
            </label>
          )}
          <label>
            Correct a prior item (optional)
            <select
              value={original}
              onChange={(e) => setOriginal(e.target.value)}
            >
              <option value="">New event</option>
              {events.map((e) => (
                <option
                  key={`${e.id}-${e.revision}`}
                  value={`${e.id}:${e.revision}`}
                >
                  {label(e.kind)} · {money(e.amount_minor)} · revision{" "}
                  {e.revision}
                </option>
              ))}
            </select>
          </label>
          <label>
            Reason
            <input
              maxLength={300}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </label>
        </div>
        <button
          className="ws-primary"
          disabled={
            busy ||
            !kind ||
            minor === null ||
            !debtor ||
            !creditor ||
            !subject ||
            !economicDate ||
            !posting ||
            !policy ||
            (kind !== "payout_request" &&
              !eventPolicies.some(
                (r: Json) =>
                  r.policy_id === policy &&
                  r.id === eventPolicy &&
                  r.kind === kind,
              )) ||
            reason.trim().length < 3
          }
          onClick={() =>
            command(
              "SUBMIT_EVENT",
              {
                case_id: data.case_id,
                event: {
                  id: original
                    ? original.split(":")[0]
                    : `event-${crypto.randomUUID()}`,
                  revision: original ? Number(original.split(":")[1]) + 1 : 1,
                  kind,
                  amount_minor: minor,
                  currency: "USD",
                  debtor_id: debtor,
                  creditor_id: creditor,
                  subject_id: subject,
                  reason,
                  economic_date: economicDate,
                  posting_period: posting,
                  policy_id: policy,
                  ...(kind !== "payout_request"
                    ? { event_policy_id: eventPolicy }
                    : {}),
                  ...(original
                    ? {
                        original_id: original.split(":")[0],
                        original_revision: Number(original.split(":")[1]),
                        original_hash: events.find(
                          (e) =>
                            e.id === original.split(":")[0] &&
                            e.revision === Number(original.split(":")[1]),
                        )?.hash,
                      }
                    : {}),
                },
              },
              "finance",
            )
          }
        >
          Submit request
        </button>
      </section>
      <section className="ws-panel ws-padded">
        <h2>Event review</h2>
        {events.length ? (
          events.map((e) => (
            <div className="md-event" key={`${e.id}-${e.revision}`}>
              <div>
                <strong>
                  {label(e.kind)} · {money(e.amount_minor)}
                </strong>
                <p>
                  {e.reason} · {label(e.status)}
                </p>
                <small>
                  {e.id} · revision {e.revision} · service {e.economic_date} ·
                  posting {e.posting_period}
                </small>
              </div>
              {e.status === "draft" && (
                <div>
                  <button
                    className="ws-secondary"
                    disabled={busy}
                    onClick={() =>
                      command(
                        "REVIEW_EVENT",
                        {
                          case_id: data.case_id,
                          event_id: e.id,
                          revision: e.revision,
                          expected_hash: e.hash,
                          decision: "approved",
                        },
                        "finance",
                      )
                    }
                  >
                    Approve exact event
                  </button>
                  <button
                    className="ws-link"
                    disabled={busy}
                    onClick={() =>
                      command(
                        "REVIEW_EVENT",
                        {
                          case_id: data.case_id,
                          event_id: e.id,
                          revision: e.revision,
                          expected_hash: e.hash,
                          decision: "rejected",
                        },
                        "finance",
                      )
                    }
                  >
                    Reject
                  </button>
                </div>
              )}
            </div>
          ))
        ) : (
          <p className="md-help">No events have been requested.</p>
        )}
      </section>
      <PaymentEvidence data={data} busy={busy} command={command} />
    </>
  );
}
function PaymentEvidence({
  data,
  busy,
  command,
}: {
  data: Data;
  busy: boolean;
  command: Command;
}) {
  const parties = (data.parties || []) as Json[],
    payments = (data.payments || []) as Json[],
    applications = (data.payment_applications || []) as Json[],
    runs = (data.runs || []) as Json[];
  const [amount, setAmount] = useState(""),
    [debtor, setDebtor] = useState(""),
    [creditor, setCreditor] = useState(""),
    [status, setStatus] = useState("pending"),
    [paymentId, setPaymentId] = useState(""),
    [runId, setRunId] = useState(""),
    [applied, setApplied] = useState(""),
    [reason, setReason] = useState(""),
    [posting, setPosting] = useState("2026-10");
  const minor = dollarsToCents(amount),
    appliedMinor = dollarsToCents(applied),
    payment = payments.find((p) => `${p.id}:${p.revision}` === paymentId);
  return (
    <>
      <section className="ws-panel ws-padded">
        <h2>Payment evidence</h2>
        <p className="md-help">
          Pending reports and payment requests do not reduce a balance. Only a
          confirmed payment can be applied to an eligible result.
        </p>
        <div className="ws-form-grid">
          <label>
            From
            <select value={debtor} onChange={(e) => setDebtor(e.target.value)}>
              <option value="">Choose party</option>
              {parties.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            To
            <select
              value={creditor}
              onChange={(e) => setCreditor(e.target.value)}
            >
              <option value="">Choose party</option>
              {parties.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Reported amount (USD)
            <input
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </label>
          <label>
            Source status
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="pending">Pending</option>
              <option value="confirmed">Confirmed</option>
            </select>
          </label>
        </div>
        <button
          className="ws-secondary"
          disabled={
            busy ||
            !debtor ||
            !creditor ||
            debtor === creditor ||
            minor === null ||
            minor === "0"
          }
          onClick={() =>
            command(
              "RECORD_PAYMENT",
              {
                case_id: data.case_id,
                payment: {
                  id: `payment-${crypto.randomUUID()}`,
                  revision: 1,
                  amount_minor: minor,
                  currency: "USD",
                  debtor_id: debtor,
                  creditor_id: creditor,
                  status,
                  observed_at: new Date().toISOString(),
                },
              },
              "finance",
            )
          }
        >
          Record mock evidence
        </button>
        {payments.map((p) => (
          <div className="md-event" key={`${p.id}-${p.revision}`}>
            <strong>
              {money(p.amount_minor)} · {label(p.status)}
            </strong>
            <small>
              Observed {p.observed_at} · {p.id} v{p.revision}
            </small>
          </div>
        ))}
        <div className="ws-form-grid">
          <label>
            Confirmed payment
            <select
              value={paymentId}
              onChange={(e) => setPaymentId(e.target.value)}
            >
              <option value="">Choose confirmed evidence</option>
              {payments
                .filter((p) => p.status === "confirmed")
                .map((p) => (
                  <option
                    key={`${p.id}-${p.revision}`}
                    value={`${p.id}:${p.revision}`}
                  >
                    {money(p.amount_minor)} · {p.id}
                  </option>
                ))}
            </select>
          </label>
          <label>
            Completed result
            <select value={runId} onChange={(e) => setRunId(e.target.value)}>
              <option value="">Choose result</option>
              {runs
                .filter((r) => r.status === "completed")
                .map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.knowledge_cutoff} · {r.id}
                  </option>
                ))}
            </select>
          </label>
          <label>
            Amount to apply (USD)
            <input
              inputMode="decimal"
              value={applied}
              onChange={(e) => setApplied(e.target.value)}
            />
          </label>
          <label>
            Application or reversal posting period
            <input
              type="month"
              value={posting}
              onChange={(e) => setPosting(e.target.value)}
            />
          </label>
          <label>
            Reason
            <input
              value={reason}
              maxLength={300}
              onChange={(e) => setReason(e.target.value)}
            />
          </label>
        </div>
        <button
          className="ws-secondary"
          disabled={
            busy ||
            !payment ||
            !runId ||
            appliedMinor === null ||
            appliedMinor === "0" ||
            reason.trim().length < 3
          }
          onClick={() =>
            payment &&
            command(
              "APPLY_PAYMENT",
              {
                case_id: data.case_id,
                payment_id: payment.id,
                payment_revision: payment.revision,
                run_id: runId,
                output_id: data.case_id === "advisor" ? "payable" : "net",
                amount_minor: appliedMinor,
                posting_period: posting,
                reason,
              },
              "finance",
            )
          }
        >
          Apply confirmed payment
        </button>
        {applications.map((a) => (
          <div className="md-event" key={a.id}>
            <div>
              <strong>Payment applied · {money(a.amount_minor)}</strong>
              <p>
                {label(a.status)} · {a.reason}
              </p>
              <small>{a.id}</small>
            </div>
            {a.status !== "reversed" && (
              <button
                className="ws-link"
                disabled={busy || reason.trim().length < 3}
                onClick={() =>
                  command(
                    "REVERSE_PAYMENT_APPLICATION",
                    {
                      case_id: data.case_id,
                      application_id: a.id,
                      posting_period: posting,
                      reason,
                    },
                    "finance",
                  )
                }
              >
                Reverse application
              </button>
            )}
          </div>
        ))}
      </section>
      <section className="ws-panel ws-padded">
        <h2>Statement preview</h2>
        <p className="md-help">
          A saved preview retains its selected result and applications; it does
          not issue an invoice or execute a payment.
        </p>
        <div className="ws-form-grid">
          <label>
            Completed result
            <select value={runId} onChange={(e) => setRunId(e.target.value)}>
              <option value="">Choose result</option>
              {runs
                .filter((r) => r.status === "completed")
                .map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.knowledge_cutoff} · {r.id}
                  </option>
                ))}
            </select>
          </label>
          <label>
            Posting period
            <input
              type="month"
              value={posting}
              onChange={(e) => setPosting(e.target.value)}
            />
          </label>
          <label>
            Reason
            <input value={reason} onChange={(e) => setReason(e.target.value)} />
          </label>
        </div>
        <button
          className="ws-secondary"
          disabled={busy || !runId || !posting || reason.trim().length < 3}
          onClick={() =>
            command(
              "SEAL_STATEMENT",
              {
                case_id: data.case_id,
                run_id: runId,
                posting_period: posting,
                reason,
              },
              "finance",
            )
          }
        >
          Save statement preview
        </button>
      </section>
    </>
  );
}

function PredicateEditor({
  title,
  values,
  onChange,
}: {
  title: string;
  values: Record<string, unknown>;
  onChange: (v: Record<string, unknown>) => void;
}) {
  const [key, setKey] = useState(""),
    [value, setValue] = useState("");
  return (
    <div>
      <strong>{title}</strong>
      {Object.entries(values).map(([k, v]) => (
        <div key={k} className="md-event">
          <span>
            {k} = {String(v)}
          </span>
          <button
            className="ws-link"
            onClick={() => {
              const copy = { ...values };
              delete copy[k];
              onChange(copy);
            }}
          >
            Remove
          </button>
        </div>
      ))}
      <div className="ws-form-grid">
        <label>
          Fact field
          <input value={key} onChange={(e) => setKey(e.target.value)} />
        </label>
        <label>
          Required value
          <input value={value} onChange={(e) => setValue(e.target.value)} />
        </label>
      </div>
      <button
        className="ws-secondary"
        disabled={!key}
        onClick={() => {
          onChange({ ...values, [key]: value });
          setKey("");
          setValue("");
        }}
      >
        Add condition
      </button>
    </div>
  );
}

function PolicyAssignment({
  data,
  busy,
  command,
}: {
  data: Data;
  busy: boolean;
  command: Command;
}) {
  const policies = ((data.policies || []) as Json[]).filter(
      (p) => p.status === "published",
    ),
    subjects = (data.subjects || []) as Json[],
    products = (data.products || []) as Json[],
    assignments = (data.assignments || []) as Json[];
  const [policyId, setPolicyId] = useState(""),
    [subjectId, setSubjectId] = useState(""),
    [productId, setProductId] = useState(""),
    [start, setStart] = useState(""),
    [lastDay, setLastDay] = useState(""),
    [replacement, setReplacement] = useState("");
  const policy = policies.find((p) => p.id === policyId),
    previous = assignments.find((a) => a.id === replacement);
  const name = (rows: Json[], id: string) => {
    const item = rows.find((r) => r.id === id);
    return item?.name || item?.version || id;
  };
  const selectPrevious = (id: string) => {
    setReplacement(id);
    const a = assignments.find((x) => x.id === id);
    if (a) {
      setSubjectId(a.subject_id);
      setProductId(a.product_id);
      setStart(a.starts_on);
      setLastDay(dateShift(a.ends_on, -1));
    }
  };
  return (
    <section className="ws-panel ws-padded">
      <div className="ws-panel-head">
        <div>
          <h2>Assign published terms</h2>
          <p>
            Publication alone does not activate terms. Assign them
            prospectively, or replace an existing complete interval as a
            separately recorded correction.
          </p>
        </div>
      </div>
      <div className="ws-form-grid">
        <label>
          Published policy
          <select
            value={policyId}
            onChange={(e) => setPolicyId(e.target.value)}
          >
            <option value="">Choose policy</option>
            {policies.map((p) => (
              <option key={p.id} value={p.id}>
                {p.version}
              </option>
            ))}
          </select>
        </label>
        <label>
          Assignment type
          <select
            value={replacement}
            onChange={(e) => selectPrevious(e.target.value)}
          >
            <option value="">New prospective interval</option>
            {assignments.map((a) => (
              <option key={a.id} value={a.id}>
                Replace {name(subjects, a.subject_id)} ·{" "}
                {name(products, a.product_id)} · {date(a.starts_on)} –{" "}
                {inclusiveEnd(a.ends_on)} · version {a.schedule_version}
              </option>
            ))}
          </select>
        </label>
        <label>
          Subject
          <select
            value={subjectId}
            disabled={!!previous}
            onChange={(e) => setSubjectId(e.target.value)}
          >
            <option value="">Choose subject</option>
            {subjects.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Product
          <select
            value={productId}
            disabled={!!previous}
            onChange={(e) => setProductId(e.target.value)}
          >
            <option value="">Choose product</option>
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          First day
          <input
            type="date"
            value={start}
            disabled={!!previous}
            onChange={(e) => setStart(e.target.value)}
          />
        </label>
        <label>
          Last day (optional)
          <input
            type="date"
            value={lastDay}
            disabled={!!previous}
            onChange={(e) => setLastDay(e.target.value)}
          />
        </label>
      </div>
      {previous && (
        <p className="md-help">
          This correction replaces the exact full interval in a new schedule
          version. Earlier versions remain available.
        </p>
      )}
      <button
        className="ws-primary"
        disabled={
          busy ||
          !policy ||
          !subjectId ||
          !productId ||
          !start ||
          (!!lastDay && lastDay < start)
        }
        onClick={() =>
          policy &&
          command(
            "ASSIGN_POLICY",
            {
              case_id: data.case_id,
              policy_id: policy.id,
              policy_hash: policy.hash,
              subject_id: subjectId,
              product_id: productId,
              starts_on: start,
              ends_on: lastDay ? dateShift(lastDay, 1) : null,
              ...(previous
                ? {
                    supersedes_assignment_id: previous.id,
                    expected_assignment_hash: previous.hash,
                  }
                : {}),
            },
            "finance",
          )
        }
      >
        Assign policy
      </button>
      <div className="md-assignment-history">
        <h3>Assignment history</h3>
        {assignments.length ? (
          assignments.map((a) => (
            <div className="md-event" key={a.id}>
              <div>
                <strong>
                  {name(subjects, a.subject_id)} ·{" "}
                  {name(products, a.product_id)}
                </strong>
                <p>
                  {name(policies, a.policy_id)} · {date(a.starts_on)} –{" "}
                  {inclusiveEnd(a.ends_on)} · schedule version{" "}
                  {a.schedule_version}
                </p>
              </div>
              <details>
                <summary>Reference</summary>
                <small>{a.id}</small>
              </details>
            </div>
          ))
        ) : (
          <p className="md-help">No assignments are available.</p>
        )}
      </div>
    </section>
  );
}
