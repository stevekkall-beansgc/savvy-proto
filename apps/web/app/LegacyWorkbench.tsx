"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import ReconciliationDesk from "./ReconciliationDesk";
import SettlementDesk, { type SettlementLedger } from "./SettlementDesk";

type Money = string | number | null | undefined;
type Rule = {
  id: string;
  kind: string;
  broker_id: string;
  numerator: number;
  denominator: number;
  valid_from: string;
  valid_to: string;
  priority: number | null;
  selector: Record<string, string>;
};
type Policy = {
  id: string;
  version: number;
  clause_text: string;
  rates: Rule[];
  guarantees: Record<string, unknown>[];
  tenant_id: string;
  entity_id: string;
  currency: string;
  [key: string]: unknown;
};
type Trace = {
  winner: string;
  reason: string;
  date: string;
  exact_earned_minor: string;
  rounding: string;
  candidates: string[];
};
type Line = {
  id: string;
  customer_id: string;
  broker_id: string;
  source_id: string;
  source_revision: number;
  eligible_minor: Money;
  earned_minor: Money;
  coverage: {
    coverage_minor: Money;
    incremental_cash_minor: Money;
    allocations: { grant_id: string; applied_minor: Money }[];
  };
  trace: Trace;
  relationship_id: string;
};
type Issue = {
  code: string;
  message: string;
  source_id?: string;
  owner?: string;
  next_action?: string;
};
type Run = {
  id: string;
  status: string;
  business_date: string;
  knowledge_cutoff: string;
  policy_hash: string;
  input_hash: string;
  engine_version: string;
  policy_id: string;
  snapshot_id: string;
  profile: string;
  lines: Line[];
  exceptions: Issue[];
  guarantees: { broker_id: string; obligation_minor: Money; measure: Money }[];
  assumptions: string[];
  inputs?: unknown;
};
type Snapshot = {
  id: string;
  business_date: string;
  watermark: string;
  complete: boolean;
  facts: {
    id: string;
    customer_id: string;
    eligible_minor: Money;
    dimensions: Record<string, string>;
  }[];
  [key: string]: unknown;
};
type State = {
  synthetic: boolean;
  role: string;
  business_date: string;
  knowledge_cutoff: string;
  brokers: { id: string; name: string; practice: string }[];
  customers: { id: string; name: string; service: string }[];
  policy: Policy | null;
  policy_hash: string | null;
  snapshot: Snapshot | null;
  latest_run: Run | null;
  approvals: {
    id: string;
    policy_hash: string;
    role: string;
    snapshot_hash: string;
  }[];
  runs: Run[];
  source_history: Snapshot[];
  active_policy_id: string | null;
};
type Collection = {
  broker_ids: string[];
  attribution_status: string;
  id: string;
  customer_id: string;
  tenant_id: string;
  entity_id: string;
  currency: string;
  amount_minor: Money;
  operational_matched_minor: Money;
  unmatched_charge_minor: Money;
  observed_cash_minor: Money;
  invoice: unknown;
  status: string;
  unknown_reason: string;
  reversed_receipt_minor: Money;
  matches: {
    id: string;
    receipt_id: string;
    minor_units: Money;
    status: string;
    reversal_reason: string | null;
  }[];
  receipts: {
    id: string;
    status: string;
    revision: number;
    previous_view_cutoff?: string;
    amount_minor: Money;
    suggested_match_minor: Money;
    unapplied_minor: Money;
  }[];
};
type Tab =
  | "Book overview"
  | "Policy studio"
  | "Sources & runs"
  | "Collections"
  | "Settlement desk"
  | "Reconciliation"
  | "Review packet";
const tabs: Tab[] = [
  "Book overview",
  "Policy studio",
  "Sources & runs",
  "Collections",
  "Settlement desk",
  "Reconciliation",
  "Review packet",
];
const query = "{ workbench collections entitlementLedger }";
const mutation =
  "mutation Command($action:Command!,$input:JSON!,$key:String!){workbenchCommand(action:$action,input:$input,idempotencyKey:$key){data errors{code message path}}}";

function money(value: Money) {
  if (value === null || value === undefined) return "Unknown";
  const n = BigInt(value),
    sign = n < 0n ? "−" : "",
    a = n < 0n ? -n : n;
  return `${sign}$${(a / 100n).toLocaleString("en-US")}.${(a % 100n).toString().padStart(2, "0")}`;
}
function formatCutoff(value: string) {
  return (
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value)) + " ET"
  );
}
function download(name: string, value: unknown) {
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(value, null, 2)], { type: "application/json" }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  URL.revokeObjectURL(url);
}
function Pill({
  children,
  tone = "green",
}: {
  children: React.ReactNode;
  tone?: "green" | "amber" | "gray";
}) {
  return <span className={`pill ${tone}`}>{children}</span>;
}
function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>;
}

export default function Page() {
  const [reconciliationRefresh, setReconciliationRefresh] = useState(0);
  const [ledger, setLedger] = useState<SettlementLedger | null>(null);
  const [cashCutoff, setCashCutoff] = useState<string | null>(null);
  const [cashReason, setCashReason] = useState("");
  const [data, setData] = useState<State | null>(null),
    [collections, setCollections] = useState<Collection[]>([]);
  const [tab, setTab] = useState<Tab>("Book overview"),
    [broker, setBroker] = useState("broker-alex"),
    [role, setRole] = useState("operator");
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [notice, setNotice] = useState("");
  const [draft, setDraft] = useState<Policy | null>(null),
    [selectedCustomer, setSelectedCustomer] = useState<string | null>(null),
    [packet, setPacket] = useState<Record<string, unknown> | null>(null),
    [viewedRun, setViewedRun] = useState<Run | null>(null);
  const sourceInput = useRef<HTMLInputElement>(null);
  const [floorInput, setFloorInput] = useState("0.00");
  useEffect(() => {
    const amount = BigInt(
      String(
        draft?.guarantees.find((g) => g.broker_id === broker)?.threshold || 0,
      ),
    );
    setFloorInput(
      `${amount / 100n}.${(amount % 100n).toString().padStart(2, "0")}`,
    );
  }, [draft?.id, broker]);
  const request = useCallback(
    async (query: string, variables: unknown = {}, asRole = role) => {
      const res = await fetch("/api/graphql", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Demo-Role": asRole },
        body: JSON.stringify({ query, variables }),
      });
      const body = await res.json();
      if (!res.ok || body.errors?.length)
        throw new Error(
          body.errors?.[0]?.message ||
            body.error ||
            "The local service could not complete this request.",
        );
      return body.data;
    },
    [role],
  );
  const load = useCallback(async () => {
    const result = await request(query);
    setError("");
    setData(result.workbench);
    setCollections(result.collections);
    setLedger(result.entitlementLedger);
    setCashCutoff(null);
    setDraft(result.workbench.policy);
    if (
      result.workbench.brokers.length &&
      !result.workbench.brokers.some((b: { id: string }) => b.id === broker)
    )
      setBroker(result.workbench.brokers[0].id);
  }, [request, broker]);
  useEffect(() => {
    setData(null);
    setViewedRun(null);
    setPacket(null);
    setError("");
    setNotice("");
    load().catch((e) => setError(e.message));
  }, [role]); // Intentional: broker selection is local and does not reload edits.
  async function command(action: string, input: unknown, asRole = role) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const r = await request(
        mutation,
        { action, input, key: crypto.randomUUID() },
        asRole,
      );
      if (r.workbenchCommand.errors.length)
        throw new Error(
          r.workbenchCommand.errors
            .map((e: Issue) => `${e.code}: ${e.message}`)
            .join("; "),
        );
      await load();
      setReconciliationRefresh((n) => n + 1);
      setViewedRun(null);
      setPacket(null);
      if (action === "CONSUME_ENTITLEMENT" || action === "REVERSE_ENTITLEMENT")
        setNotice(
          "Recorded coverage updated. Saved projections are retained; run a new projection to include the changed balance. No payment was executed.",
        );
      if (["RECORD_INVOICE_APPLICATION", "REVERSE_INVOICE_APPLICATION", "RECORD_BANK_BATCH", "REVERSE_BANK_BATCH", "CLOSE_RECONCILIATION"].includes(action))
        setNotice("Synthetic evidence recorded. No accounting entry was posted.");
      return r.workbenchCommand.data;
    } catch (e) {
      setError((e as Error).message);
      setReconciliationRefresh((n) => n + 1);
      return null;
    } finally {
      setBusy(false);
    }
  }
  async function project() {
    if (!data?.policy || !data.snapshot) return;
    const r = await command("PROJECT", {
      policy_id: data.policy.id,
      snapshot_id: data.snapshot.id,
      business_date: data.snapshot.business_date,
      knowledge_cutoff: data.knowledge_cutoff,
    });
    if (r) {
      setNotice(
        `Saved a ${r.status} projection. Opening advance balances are unchanged.`,
      );
      setTab("Book overview");
    }
  }
  async function savePolicy() {
    if (floorInput && !/^\d{1,13}(?:\.\d{0,2})?$/.test(floorInput)) {
      setError(
        "Enter a nonnegative USD floor with at most two decimal places.",
      );
      return;
    }
    const r = await command("SAVE_POLICY", {
      policy: draft,
      expected_hash: data?.policy_hash,
    });
    if (r)
      setNotice(
        `${r.id} saved as a new draft. Earlier results and reviews are retained. Run a projection to inspect the change.`,
      );
  }
  async function showPacket() {
    if (!run) return;
    setBusy(true);
    setError("");
    try {
      const r = await request("query($id:ID!){reviewPacket(runId:$id)}", {
        id: run.id,
      });
      setPacket(r.reviewPacket);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function importFile(file: File) {
    if (file.size > 900000) {
      setError("Use a synthetic JSON fixture smaller than 900 KB.");
      return;
    }
    try {
      const snapshot = JSON.parse(await file.text());
      const r = await command("IMPORT_SNAPSHOT", { snapshot });
      if (r)
        setNotice(
          r.code
            ? `${r.code}: ${r.next_action}`
            : `${r.id} imported; quality: ${r.quality}. Run a projection to publish an outcome.`,
        );
    } catch {
      setError("The fixture must contain valid synthetic JSON.");
    }
  }
  const run = viewedRun || data?.latest_run;
  const book = data?.brokers.find((b) => b.id === broker);
  const lines = run?.lines.filter((l) => l.broker_id === broker) || [];
  const customers =
    data?.customers.filter((c) => lines.some((l) => l.customer_id === c.id)) ||
    [];
  const canOperate = role === "operator" || role === "finance";
  const currentPolicyHash = data?.policy_hash;
  const approvalRoles =
    data?.approvals
      .filter((a) => a.policy_hash === currentPolicyHash)
      .map((a) => a.role) || [];
  const [bookTotals, setBookTotals] = useState<{
    earned: Money;
    coverage: Money;
    incremental: Money;
  } | null>(null);
  useEffect(() => {
    setBookTotals(null);
    if (!data) return;
    request(
      "query($id:ID!,$runId:ID){brokerBook(brokerId:$id,runId:$runId){earned{minorUnits} coverage{minorUnits} incrementalCash{minorUnits}}}",
      { id: broker, runId: viewedRun?.id },
    )
      .then((r) =>
        setBookTotals({
          earned: r.brokerBook.earned?.minorUnits,
          coverage: r.brokerBook.coverage?.minorUnits,
          incremental: r.brokerBook.incrementalCash?.minorUnits,
        }),
      )
      .catch((e) => setError(e.message));
  }, [data, broker, viewedRun, request]);
  function changeRate(index: number, value: string) {
    if (!draft) return;
    const next = structuredClone(draft);
    next.rates[index].numerator = Number(value);
    next.rates[index].denominator = 100;
    setDraft(next);
  }
  function setGuarantee(value: string) {
    if (!draft) return;
    setFloorInput(value);
    if (value && !/^\d{1,13}(?:\.\d{0,2})?$/.test(value)) return;
    const [whole = "0", fraction = ""] = value.split(".");
    const n = BigInt((whole || "0") + fraction.padEnd(2, "0")).toString();
    const next = structuredClone(draft);
    next.guarantees = next.guarantees.filter((g) => g.broker_id !== broker);
    if (BigInt(n) > 0n)
      next.guarantees.push({
        id: `guarantee-${broker}`,
        tenant_id: next.tenant_id,
        entity_id: next.entity_id,
        currency: "USD",
        kind: "floor",
        aggregation: "sum",
        metric: "earned_minor",
        metric_unit: "USD_minor",
        threshold_unit: "USD_minor",
        payment_unit: "USD_minor",
        stacking: "exclusive",
        filters: {},
        threshold: n,
        broker_id: broker,
        group: "broker",
        period: { start: "2026-11-01", end_exclusive: "2026-12-01" },
      });
    setDraft(next);
  }
  const guaranteeResult = run?.guarantees.find((g) => g.broker_id === broker);

  return (
    <div className="app">
      <aside className="sidebar">
        <a href="#main" className="skip">
          Skip to content
        </a>
        <div className="brand">
          <img
            className="savvy-logo"
            src="/savvy/logo.svg"
            alt="Savvy"
            width="112"
            height="39"
          />
          <small>ADVISOR ECONOMICS PROTOTYPE</small>
        </div>
        <div className="workspace">
          <div>
            Advisor workspace<small>Fictional book · Local prototype</small>
          </div>
        </div>
        <p className="nav-label">WORKSPACE</p>
        <nav aria-label="Workbench views">
          {tabs.filter((name) => role !== "advisor" || name !== "Reconciliation").map((name) => (
            <button
              key={name}
              aria-current={tab === name ? "page" : undefined}
              onClick={() => {
                setTab(name);
                setError("");
                setNotice("");
              }}
            >
              <span className="nav-icon">
                {["▦", "≋", "◫", "↔", "⇄", "◈", "▤"][tabs.indexOf(name)]}
              </span>
              {name}
              {tab === name && <span className="nav-dot" />}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <span className="live-dot" /> Local workspace
          <div>Fictional data. No provider connection.</div>
          <p>
            Illustrative economics, independently built.
            <br />
            No Savvy systems or records accessed.
          </p>
        </div>
      </aside>
      <div className="main-wrap">
        <header className="topbar">
          <div>
            Workspace <span>/</span> {tab}
          </div>
          <label className="role-picker">
            Demo role{" "}
            <select
              aria-label="Simulated demo role"
              value={role}
              onChange={(e) => { if (e.target.value === "advisor" && tab === "Reconciliation") setTab("Book overview"); setRole(e.target.value); }}
            >
              {["operator", "finance", "legal", "advisor", "auditor"].map(
                (r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ),
              )}
            </select>
          </label>
        </header>
        <main id="main">
          <div className="demo-banner">
            <span className="demo-symbol">◈</span>
            <strong>Synthetic demonstration</strong>
            <span>Every customer, agreement and amount is fictional.</span>
            <Pill tone="gray">No live connection</Pill>
          </div>
          {error && (
            <div role="alert" className="alert error">
              {error}
              <button onClick={() => setError("")} aria-label="Dismiss error">
                ×
              </button>
            </div>
          )}
          {notice && (
            <div role="status" className="alert success">
              {notice}
            </div>
          )}
          {!data ? (
            <Empty>
              {error ? (
                <>
                  The local services need to be running.
                  <button
                    className="secondary"
                    onClick={() => load().catch((e) => setError(e.message))}
                  >
                    Try again
                  </button>
                </>
              ) : (
                "Opening the workbench…"
              )}
            </Empty>
          ) : (
            <>
              <div className="page-heading">
                <div>
                  <p className="eyebrow">
                    {tab === "Book overview"
                      ? "YOUR BOOK, EXPLAINED"
                      : "ADVISOR ECONOMICS"}
                  </p>
                  <h1>
                    {tab === "Book overview"
                      ? "Your book, clearly in view."
                      : tab}
                  </h1>
                  <p>
                    {tab === "Book overview"
                      ? "Follow customer economics from the source to the advisor’s expected payment."
                      : tab === "Policy studio"
                        ? "Configure supported terms, compare outcomes, and keep every version."
                        : tab === "Sources & runs"
                          ? "Inspect fictional source batches and reproduce an earlier result."
                          : tab === "Reconciliation"
                            ? "Review independently supplied invoice and bank evidence for a period."
                            : tab === "Settlement desk"
                            ? "Record eligible coverage and restore the original grant when a decision changes."
                            : tab === "Collections"
                              ? "Keep expected charges, observed cash and accounting evidence separate."
                              : "Bring the language, structured terms and worked examples into one review."}
                  </p>
                </div>
                <button
                  className="primary"
                  onClick={project}
                  disabled={busy || !canOperate || !data.policy}
                >
                  {busy ? "Working…" : "↻  Run projection"}
                </button>
              </div>
              <div className="contextbar">
                <label>
                  Broker{" "}
                  <select
                    aria-label="Broker"
                    value={broker}
                    onChange={(e) => {
                      setBroker(e.target.value);
                      setSelectedCustomer(null);
                    }}
                  >
                    {data.brokers.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.name}
                      </option>
                    ))}
                  </select>
                </label>
                <div>
                  <small>BUSINESS DATE</small>
                  <strong>{data.business_date}</strong>
                </div>
                <div>
                  <small>PROJECTION CUTOFF</small>
                  <strong>
                    {formatCutoff(
                      run?.knowledge_cutoff || data.knowledge_cutoff,
                    )}
                  </strong>
                </div>
                <div className="context-status">
                  <Pill tone={run?.status === "completed" ? "green" : "amber"}>
                    {run?.status || "Not yet run"}
                  </Pill>
                  <small>USD · Service-date basis</small>
                </div>
              </div>

              {tab === "Book overview" && (
                <>
                  {data.policy &&
                    run &&
                    run.policy_id !== data.policy.id &&
                    !viewedRun && (
                      <div className="alert">
                        The overview shows saved {run.policy_id}. Current draft{" "}
                        {data.policy.id} needs a new projection.
                      </div>
                    )}
                  {viewedRun && (
                    <div className="alert">
                      Viewing a saved historical run.{" "}
                      <button
                        className="text-button"
                        onClick={() => setViewedRun(null)}
                      >
                        Return to latest
                      </button>
                    </div>
                  )}
                  {!run ? (
                    <Empty>
                      Ready when you are. Run the first projection to inspect
                      the fictional book.
                    </Empty>
                  ) : (
                    <>
                      <section className="metrics" aria-label="Advisor outcome">
                        <div className="metric accent">
                          <span>Expected incremental cash</span>
                          <strong>{money(bookTotals?.incremental)}</strong>
                          <small>
                            After coverage · before guarantee true-up
                          </small>
                          <div className="metric-rule" />
                        </div>
                        <div className="metric">
                          <span>Advisor earned</span>
                          <strong>{money(bookTotals?.earned)}</strong>
                          <small>
                            Rate applied to eligible fee observations
                          </small>
                        </div>
                        <div className="metric">
                          <span>Advance coverage</span>
                          <strong>{money(bookTotals?.coverage)}</strong>
                          <small>
                            Simulated application · original cash separate
                          </small>
                        </div>
                        <div className="metric">
                          <span>Monthly guarantee</span>
                          <strong>
                            {guaranteeResult
                              ? money(guaranteeResult.obligation_minor)
                              : "Not configured"}
                          </strong>
                          <small>
                            {guaranteeResult
                              ? "Provisional true-up on supplied earnings"
                              : "A floor can be added in Policy studio"}
                          </small>
                        </div>
                      </section>
                      <div className="overview-grid">
                        <section className="panel roster">
                          <div className="panel-heading">
                            <div>
                              <h2>{book?.name}’s customer book</h2>
                              <p>
                                Fee observations → selected rate → advisor
                                outcome
                              </p>
                            </div>
                            <Pill tone="gray">
                              {customers.length} customers
                            </Pill>
                          </div>
                          <div className="table-scroll">
                            <table>
                              <thead>
                                <tr>
                                  <th>Customer / service</th>
                                  <th>Eligible fees</th>
                                  <th>Advisor earned</th>
                                  <th>Incremental cash</th>
                                  <th>Rule</th>
                                </tr>
                              </thead>
                              <tbody>
                                {lines.map((line) => {
                                  const customer = data.customers.find(
                                    (c) => c.id === line.customer_id,
                                  );
                                  return (
                                    <tr key={line.id}>
                                      <td>
                                        <button
                                          className="customer-link"
                                          onClick={() =>
                                            setSelectedCustomer(
                                              selectedCustomer === line.id
                                                ? null
                                                : line.id,
                                            )
                                          }
                                        >
                                          {customer?.name || line.customer_id}
                                          <span> ↗</span>
                                        </button>
                                        <small>{customer?.service}</small>
                                      </td>
                                      <td>{money(line.eligible_minor)}</td>
                                      <td>{money(line.earned_minor)}</td>
                                      <td>
                                        {money(
                                          line.coverage.incremental_cash_minor,
                                        )}
                                      </td>
                                      <td>
                                        <Pill
                                          tone={
                                            line.trace.winner.includes(
                                              "override",
                                            )
                                              ? "green"
                                              : "gray"
                                          }
                                        >
                                          {line.trace.winner.split("-").at(-1)}
                                        </Pill>
                                      </td>
                                    </tr>
                                  );
                                })}
                              </tbody>
                            </table>
                          </div>
                          {lines.length === 0 && (
                            <Empty>
                              The calculation is withheld. Resolve the
                              exceptions below and run a new projection.
                            </Empty>
                          )}
                          <div className="table-footer">
                            <span>
                              Customer detail stays linked to its original
                              source.
                            </span>
                            <button
                              className="text-button"
                              onClick={() => setTab("Sources & runs")}
                            >
                              View source & run →
                            </button>
                          </div>
                        </section>
                        <section className="panel explanation">
                          <p className="eyebrow">WHY THIS OUTCOME?</p>
                          <h2>Terms with a trace.</h2>
                          <ol className="steps">
                            <li>
                              <span>1</span>
                              <div>
                                <strong>Start with eligible fees</strong>
                                <p>
                                  Use supplied customer-level observations.
                                  Missing evidence is held for review.
                                </p>
                              </div>
                            </li>
                            <li>
                              <span>2</span>
                              <div>
                                <strong>Resolve the matching terms</strong>
                                <p>
                                  Specific overrides take precedence, then
                                  active promotion, then standard share.
                                </p>
                              </div>
                            </li>
                            <li>
                              <span>3</span>
                              <div>
                                <strong>Apply eligible coverage</strong>
                                <p>
                                  Share one simulated advance balance across the
                                  book, in a stable order.
                                </p>
                              </div>
                            </li>
                          </ol>
                          <button
                            className="secondary full"
                            onClick={() => setTab("Policy studio")}
                          >
                            Inspect commercial terms →
                          </button>
                        </section>
                      </div>
                      {selectedCustomer &&
                        lines
                          .filter((l) => l.id === selectedCustomer)
                          .map((l) => (
                            <section className="panel detail" key={l.id}>
                              <div className="panel-heading">
                                <h2>
                                  Calculation detail ·{" "}
                                  {
                                    data.customers.find(
                                      (c) => c.id === l.customer_id,
                                    )?.name
                                  }
                                </h2>
                                <button
                                  className="text-button"
                                  onClick={() => setSelectedCustomer(null)}
                                >
                                  Close
                                </button>
                              </div>
                              <dl className="detail-grid">
                                <div>
                                  <dt>Source record / revision</dt>
                                  <dd>
                                    {l.source_id} / {l.source_revision}
                                  </dd>
                                </div>
                                <div>
                                  <dt>Effective assignment</dt>
                                  <dd>{l.relationship_id}</dd>
                                </div>
                                <div>
                                  <dt>Winning rule</dt>
                                  <dd>{l.trace.winner}</dd>
                                </div>
                                <div>
                                  <dt>Exact earned cents before rounding</dt>
                                  <dd>{l.trace.exact_earned_minor}</dd>
                                </div>
                                <div>
                                  <dt>Selection reason</dt>
                                  <dd>{l.trace.reason}</dd>
                                </div>
                                <div>
                                  <dt>Rounding boundary</dt>
                                  <dd>{l.trace.rounding}</dd>
                                </div>
                              </dl>
                              <p>
                                Matching candidates:{" "}
                                {l.trace.candidates.join(", ")}
                              </p>
                              <p>
                                Coverage:{" "}
                                {l.coverage.allocations.length
                                  ? l.coverage.allocations
                                      .map(
                                        (a) =>
                                          `${a.grant_id}: ${money(a.applied_minor)}`,
                                      )
                                      .join("; ")
                                  : "No eligible coverage"}
                              </p>
                              <button
                                className="secondary"
                                onClick={() => setTab("Collections")}
                              >
                                Open charge and cash evidence →
                              </button>
                            </section>
                          ))}
                      {run.exceptions.length > 0 && (
                        <section className="panel exceptions">
                          <h2>Held for review</h2>
                          {run.exceptions.map((e, i) => (
                            <div key={i}>
                              <strong>{e.code}</strong>
                              <p>
                                {e.source_id}: {e.message}
                              </p>
                              <small>
                                {e.owner} · {e.next_action}
                              </small>
                            </div>
                          ))}
                        </section>
                      )}
                      <section className="run-strip">
                        <div>
                          <span className="live-dot" />
                          <strong>Reproducible snapshot</strong>
                          <p>{run.id}</p>
                        </div>
                        <div>
                          <small>POLICY FINGERPRINT</small>
                          <code>{run.policy_hash.slice(0, 16)}…</code>
                        </div>
                        <div>
                          <small>INPUT FINGERPRINT</small>
                          <code>{run.input_hash.slice(0, 16)}…</code>
                        </div>
                        <button
                          className="secondary"
                          onClick={() => download(`${run.id}.json`, run)}
                        >
                          ↓ Export run
                        </button>
                      </section>
                      <details className="assumptions">
                        <summary>What these numbers assume</summary>
                        <ul>
                          {run.assumptions.map((a) => (
                            <li key={a}>{a}</li>
                          ))}
                        </ul>
                      </details>
                    </>
                  )}
                </>
              )}

              {tab === "Policy studio" &&
                (!draft ? (
                  <Empty>
                    This demo role can see its book, but cannot inspect or edit
                    other commercial policies.
                  </Empty>
                ) : (
                  <>
                    <div className="two-columns">
                      <section className="panel">
                        <div className="panel-heading">
                          <div>
                            <h2>Rate hierarchy</h2>
                            <p>
                              {draft.id} · Replacement rates · Service-date
                              basis
                            </p>
                          </div>
                          <Pill tone="gray">Draft configuration</Pill>
                        </div>
                        <div className="rule-list">
                          {draft.rates.map(
                            (r, i) =>
                              r.broker_id === broker && (
                                <div className="rule-card" key={r.id}>
                                  <div>
                                    <Pill
                                      tone={
                                        r.kind === "override" ? "green" : "gray"
                                      }
                                    >
                                      {r.kind}
                                    </Pill>
                                    <h3>
                                      {r.kind === "standard"
                                        ? "Standard advisor share"
                                        : r.kind === "promotion"
                                          ? "November promotion"
                                          : "Managed service override"}
                                    </h3>
                                    <p>
                                      {Object.entries(r.selector)
                                        .map(([k, v]) => `${k}: ${v}`)
                                        .join(", ") ||
                                        "All approved customer and product types"}
                                    </p>
                                    <small>
                                      {r.valid_from} → {r.valid_to} (exclusive)
                                    </small>
                                  </div>
                                  <label>
                                    Share %
                                    <input
                                      type="number"
                                      min="0"
                                      max="100"
                                      step="1"
                                      aria-label={`${r.kind} share percent`}
                                      value={r.numerator}
                                      onChange={(e) =>
                                        changeRate(i, e.target.value)
                                      }
                                      disabled={role !== "operator"}
                                    />
                                  </label>
                                </div>
                              ),
                          )}
                        </div>
                      </section>
                      <section className="panel padded">
                        <h2>Monthly earnings floor</h2>
                        <p>
                          One broker, one calendar month. The floor uses earned
                          amounts before prepaid coverage.
                        </p>
                        <label className="field">
                          Floor (USD)
                          <input
                            aria-label="Monthly floor in USD"
                            inputMode="decimal"
                            type="text"
                            value={floorInput}
                            onChange={(e) => setGuarantee(e.target.value)}
                            disabled={role !== "operator"}
                          />
                        </label>
                        <div className="note">
                          <strong>A provisional true-up</strong>
                          <p>
                            Only supplied snapshot earnings are measured. This
                            does not forecast unseen activity for the rest of
                            the month. Zero removes this broker’s floor.
                          </p>
                        </div>
                        <h3>Rule boundaries</h3>
                        <p>
                          USD only. Approved fictional dimensions. Ambiguous
                          matches block a result. Other guarantee metrics,
                          stacking and conversion mechanisms remain unsupported.
                        </p>
                      </section>
                    </div>
                    <section className="panel padded">
                      <h2>Draft clause language</h2>
                      <p>
                        Keep the wording aligned with the structured terms. Both
                        are reviewed together; editing a rate does not rewrite
                        the language.
                      </p>
                      <label className="field">
                        <span className="sr-only">Draft commercial clause</span>
                        <textarea
                          aria-label="Draft commercial clause"
                          rows={5}
                          value={draft.clause_text}
                          onChange={(e) =>
                            setDraft({ ...draft, clause_text: e.target.value })
                          }
                          disabled={role !== "operator"}
                        />
                      </label>
                      <div className="actions">
                        <button
                          className="primary"
                          disabled={busy || role !== "operator"}
                          onClick={savePolicy}
                        >
                          Save new policy version
                        </button>
                        <span>
                          Saved versions retain earlier terms and invalidate
                          previous hash-bound reviews.
                        </span>
                      </div>
                    </section>
                  </>
                ))}

              {tab === "Sources & runs" && (
                <>
                  <section className="panel padded">
                    <div className="panel-heading">
                      <div>
                        <h2>Internal source · fictional adapter</h2>
                        <p>
                          No broker feed, credentials or live account is needed.
                        </p>
                      </div>
                      <Pill tone={data.snapshot?.complete ? "green" : "amber"}>
                        {data.snapshot?.complete
                          ? "Complete synthetic batch"
                          : "Restricted or unavailable"}
                      </Pill>
                    </div>
                    {data.snapshot && (
                      <>
                        <dl className="detail-grid">
                          <div>
                            <dt>Snapshot</dt>
                            <dd>{data.snapshot.id}</dd>
                          </div>
                          <div>
                            <dt>Business watermark</dt>
                            <dd>{data.snapshot.watermark}</dd>
                          </div>
                          <div>
                            <dt>Observation count</dt>
                            <dd>{data.snapshot.facts.length}</dd>
                          </div>
                        </dl>
                        <div className="actions">
                          <button
                            className="secondary"
                            onClick={() =>
                              download("synthetic-snapshot.json", data.snapshot)
                            }
                          >
                            ↓ Download source fixture
                          </button>
                          <button
                            className="secondary"
                            disabled={role !== "operator" || busy}
                            onClick={() => sourceInput.current?.click()}
                          >
                            Import synthetic JSON
                          </button>
                          <input
                            hidden
                            type="file"
                            accept="application/json,.json"
                            ref={sourceInput}
                            onChange={(e) => {
                              const f = e.target.files?.[0];
                              if (f) importFile(f);
                              e.target.value = "";
                            }}
                          />
                        </div>
                        <p className="help">
                          A changed source record requires a new revision.
                          Conflicting content is quarantined; an import does not
                          automatically run a projection.
                        </p>
                      </>
                    )}
                  </section>
                  <section className="panel">
                    <div className="panel-heading">
                      <div>
                        <h2>Saved run history</h2>
                        <p>
                          Each result pins the full policy, source and engine
                          version.
                        </p>
                      </div>
                    </div>
                    <div className="table-scroll">
                      <table>
                        <thead>
                          <tr>
                            <th>Run</th>
                            <th>Business date</th>
                            <th>State</th>
                            <th>Policy hash</th>
                            <th>Open</th>
                          </tr>
                        </thead>
                        <tbody>
                          {data.runs.map((r) => (
                            <tr key={r.id}>
                              <td>
                                <code>{r.id.slice(0, 20)}…</code>
                              </td>
                              <td>{r.business_date}</td>
                              <td>
                                <Pill
                                  tone={
                                    r.status === "completed" ? "green" : "amber"
                                  }
                                >
                                  {r.status}
                                </Pill>
                              </td>
                              <td>
                                <code>{r.policy_hash.slice(0, 12)}…</code>
                              </td>
                              <td>
                                <button
                                  className="text-button"
                                  disabled={busy}
                                  onClick={async () => {
                                    try {
                                      const result = await request(
                                        "query($id:ID!){run(id:$id){data}}",
                                        { id: r.id },
                                      );
                                      setViewedRun(result.run.data);
                                      setTab("Book overview");
                                    } catch (e) {
                                      setError((e as Error).message);
                                    }
                                  }}
                                >
                                  Inspect →
                                </button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </section>
                </>
              )}

              {tab === "Collections" && (
                <>
                  {cashCutoff && (
                    <div className="alert">
                      Viewing evidence before a receipt reversal: {cashCutoff}.{" "}
                      <button
                        className="text-button"
                        onClick={() => load().catch((e) => setError(e.message))}
                      >
                        Return to current evidence
                      </button>
                    </div>
                  )}
                  <label className="field">
                    Reason for a cash evidence correction
                    <input
                      aria-label="Cash correction reason"
                      value={cashReason}
                      maxLength={300}
                      onChange={(e) => setCashReason(e.target.value)}
                      disabled={role !== "finance" || !!cashCutoff}
                      placeholder="Describe the fictional source or matching correction"
                    />
                  </label>
                  <div className="note wide">
                    <strong>Three independent questions</strong>
                    <p>
                      Was cash observed? Was it matched operationally to a
                      charge? Was it applied, settled or recognized in
                      accounting? One answer does not establish the others.
                    </p>
                  </div>
                  {collections
                    .filter(
                      (c) =>
                        c.broker_ids?.includes(broker) ||
                        c.attribution_status !== "resolved",
                    )
                    .map((c) => (
                      <section className="panel padded" key={c.id}>
                        <div className="panel-heading">
                          <div>
                            <h2>
                              {
                                data.customers.find(
                                  (x) => x.id === c.customer_id,
                                )?.name
                              }
                            </h2>
                            <p>{c.id}</p>
                          </div>
                          <Pill tone="amber">
                            {c.invoice
                              ? "Invoice linked · application unknown"
                              : "Charge before invoice"}
                          </Pill>
                        </div>
                        <div className="collection-metrics">
                          <div>
                            <small>Approved charge</small>
                            <strong>{money(c.amount_minor)}</strong>
                          </div>
                          <div>
                            <small>Active cash receipts</small>
                            <strong>{money(c.observed_cash_minor)}</strong>
                          </div>
                          <div>
                            <small>Operationally matched</small>
                            <strong>
                              {money(c.operational_matched_minor)}
                            </strong>
                          </div>
                          <div>
                            <small>Unmatched charge</small>
                            <strong>{money(c.unmatched_charge_minor)}</strong>
                          </div>
                        </div>
                        <div className="accounting-states">
                          <span>
                            Invoice application <b>Unknown</b>
                          </span>
                          <span>
                            Bank settled <b>Unknown</b>
                          </span>
                          <span>
                            Recognized revenue <b>Unknown</b>
                          </span>
                          <span>
                            Accounting AR <b>Unknown</b>
                          </span>
                        </div>
                        <p className="help">
                          {c.unknown_reason}. Unmatched charge is an operational
                          balance.
                        </p>
                        <div className="actions">
                          {c.receipts.map((receipt) => (
                            <button
                              key={receipt.id}
                              className="secondary"
                              disabled={
                                busy ||
                                !!cashCutoff ||
                                !canOperate ||
                                String(receipt.suggested_match_minor) === "0"
                              }
                              onClick={async () => {
                                const r = await command("MATCH", {
                                  charge_id: c.id,
                                  receipt_id: receipt.id,
                                  minor_units: receipt.suggested_match_minor,
                                });
                                if (r)
                                  setNotice(
                                    "Fictional cash matched to the charge. No invoice payment or external accounting entry was created.",
                                  );
                              }}
                            >
                              Match {money(receipt.suggested_match_minor)}{" "}
                              receipt
                            </button>
                          ))}
                          <button
                            className="secondary"
                            disabled={
                              busy ||
                              !!cashCutoff ||
                              role !== "finance" ||
                              !!c.invoice
                            }
                            onClick={async () => {
                              const invoice = {
                                id: `invoice-${c.customer_id}`,
                                tenant_id: c.tenant_id,
                                entity_id: c.entity_id,
                                currency: c.currency,
                                customer_id: c.customer_id,
                                amount_minor: c.amount_minor,
                                status: "open",
                                synthetic: true,
                              };
                              const r = await command("LINK_INVOICE", {
                                charge_id: c.id,
                                invoice,
                              });
                              if (r)
                                setNotice(
                                  "Synthetic invoice evidence linked to the existing charge. Cash was retained once; accounting application remains unknown.",
                                );
                            }}
                          >
                            Link matching fictional invoice
                          </button>
                        </div>
                        <details className="cash-history">
                          <summary>Receipt and match history</summary>
                          {c.receipts.map((receipt) => (
                            <div
                              className="receipt-history-row"
                              key={receipt.id}
                            >
                              <div>
                                <strong>{receipt.id}</strong>
                                <p>
                                  Revision {receipt.revision} · {receipt.status}{" "}
                                  · {money(receipt.amount_minor)}
                                </p>
                              </div>
                              <div className="actions">
                                <button
                                  className="secondary"
                                  disabled={
                                    busy ||
                                    role !== "finance" ||
                                    !!cashCutoff ||
                                    receipt.status !== "verified_cash" ||
                                    cashReason.trim().length < 3
                                  }
                                  onClick={async () => {
                                    const r = await command("REVERSE_RECEIPT", {
                                      receipt_id: receipt.id,
                                      expected_revision: receipt.revision,
                                      reason: cashReason,
                                    });
                                    if (r)
                                      setNotice(
                                        "Receipt evidence reversed and its internal matches released. This does not prove or execute a bank refund.",
                                      );
                                  }}
                                >
                                  Reverse fictional receipt
                                </button>
                                {receipt.previous_view_cutoff && (
                                  <button
                                    className="secondary"
                                    disabled={busy}
                                    onClick={async () => {
                                      try {
                                        const r = await request(
                                          "query($cutoff:String!){collections(knowledgeCutoff:$cutoff)}",
                                          {
                                            cutoff:
                                              receipt.previous_view_cutoff,
                                          },
                                        );
                                        setCollections(r.collections);
                                        setCashCutoff(
                                          receipt.previous_view_cutoff || null,
                                        );
                                      } catch (e) {
                                        setError((e as Error).message);
                                      }
                                    }}
                                  >
                                    View before reversal
                                  </button>
                                )}
                              </div>
                            </div>
                          ))}
                          {c.matches.map((m) => (
                            <div className="receipt-history-row" key={m.id}>
                              <div>
                                <strong>
                                  Match {m.id} · {money(m.minor_units)}
                                </strong>
                                <p>
                                  {m.status}
                                  {m.reversal_reason
                                    ? ` · ${m.reversal_reason}`
                                    : ""}
                                </p>
                              </div>
                              <button
                                className="secondary"
                                disabled={
                                  busy ||
                                  role !== "finance" ||
                                  !!cashCutoff ||
                                  m.status !== "active" ||
                                  cashReason.trim().length < 3
                                }
                                onClick={async () => {
                                  const r = await command("REVERSE_MATCH", {
                                    allocation_id: m.id,
                                    reason: cashReason,
                                  });
                                  if (r)
                                    setNotice(
                                      "The internal match was reversed. The observed receipt remains unchanged.",
                                    );
                                }}
                              >
                                Reverse match only
                              </button>
                            </div>
                          ))}
                          {c.receipts.length === 0 && (
                            <p>
                              No customer-attributed receipt evidence has been
                              supplied.
                            </p>
                          )}
                          <p className="help">
                            Original receipt versions and allocations are
                            retained. A source reversal is separate from a
                            verified bank refund.
                          </p>
                        </details>
                      </section>
                    ))}
                </>
              )}

              {tab === "Reconciliation" && role !== "advisor" && (
                <ReconciliationDesk customers={data.customers} receipts={Array.from(new Map(collections.flatMap((c) => c.receipts.filter((r) => r.status === "verified_cash" && r.amount_minor != null).map((r) => [r.id, { id: r.id, customer: c.customer_id, customer_name: data.customers.find((customer) => customer.id === c.customer_id)?.name || c.customer_id, amount_minor: String(r.amount_minor) }] as const))).values())} role={role} busy={busy} refresh={reconciliationRefresh} request={request} command={command} formatMoney={money} />
              )}
              {tab === "Settlement desk" && (
                <SettlementDesk
                  ledger={ledger}
                  broker={broker}
                  role={role}
                  busy={busy}
                  formatMoney={money}
                  command={command}
                />
              )}
              {tab === "Review packet" && (
                <>
                  <section className="panel padded">
                    <div className="panel-heading">
                      <div>
                        <h2>Review the exact version</h2>
                        <p>
                          Simulated Legal and Finance review is separate from a
                          signed contract.
                        </p>
                      </div>
                      <Pill tone="amber">No contract executed</Pill>
                    </div>
                    <div className="review-grid">
                      {["finance", "legal"].map((r) => (
                        <div key={r}>
                          <span className="review-icon">
                            {approvalRoles.includes(r) ? "✓" : "○"}
                          </span>
                          <h3>
                            {r === "finance"
                              ? "Finance review"
                              : "Legal review"}
                          </h3>
                          <p>
                            {approvalRoles.includes(r)
                              ? "Current policy has a retained review record; activation also checks current examples."
                              : "Current terms and examples need review."}
                          </p>
                          <button
                            className="secondary"
                            disabled={busy || role !== r || !data.policy}
                            onClick={async () => {
                              const result = await command("REVIEW", {
                                policy_id: data.policy?.id,
                                policy_hash: data.policy_hash,
                              });
                              if (result)
                                setNotice(
                                  `${r} approval recorded for the current policy and examples. This is simulated review only.`,
                                );
                            }}
                          >
                            Approve for demo as {r}
                          </button>
                        </div>
                      ))}
                    </div>
                    <p className="help">
                      Change the Demo role to perform its review. These
                      selectable identities are a local simulation, not
                      production authentication.
                    </p>
                    <div className="actions">
                      <button
                        className="primary"
                        disabled={busy || role !== "operator" || !data.policy}
                        onClick={async () => {
                          const r = await command("ACTIVATE", {
                            policy_id: data.policy?.id,
                            policy_hash: data.policy_hash,
                          });
                          if (r)
                            setNotice(
                              "Policy activated for this fictional demo. This does not execute a contract.",
                            );
                        }}
                      >
                        Activate reviewed demo policy
                      </button>
                      <span>
                        Active policy:{" "}
                        {data.active_policy_id ||
                          "None; projections remain draft simulations"}
                      </span>
                    </div>
                  </section>
                  <section className="panel padded">
                    <h2>Frozen review packet</h2>
                    <p>
                      The packet uses the selected saved run’s terms, examples,
                      assumptions and fingerprints. Draft edits need a new
                      projection before they appear here.
                    </p>
                    <div className="actions">
                      <button
                        className="secondary"
                        disabled={!run || busy || role === "advisor"}
                        onClick={showPacket}
                      >
                        Generate packet from saved run
                      </button>
                      {packet && (
                        <button
                          className="secondary"
                          onClick={() =>
                            download("draft-review-packet.json", packet)
                          }
                        >
                          ↓ Export packet
                        </button>
                      )}
                    </div>
                    {packet && (
                      <div className="packet">
                        <Pill tone="amber">
                          Draft · Synthetic · Not executed
                        </Pill>
                        <h3>{String(packet.title)}</h3>
                        <p className="clause">
                          {String(packet.draft_language)}
                        </p>
                        <dl className="detail-grid">
                          <div>
                            <dt>Policy hash</dt>
                            <dd>
                              <code>{String(packet.policy_hash)}</code>
                            </dd>
                          </div>
                          <div>
                            <dt>Run ID</dt>
                            <dd>{String(packet.run_id)}</dd>
                          </div>
                        </dl>
                        <p>{String(packet.review_note)}</p>
                      </div>
                    )}
                  </section>
                </>
              )}
              <footer>
                <span>Independent prototype · Savvy visual reference</span>
                <span>
                  Local only · No payment, posting or signature actions
                </span>
              </footer>
            </>
          )}
        </main>
      </div>
    </div>
  );
}
