"use client";
import { useCallback, useEffect, useState } from "react";
import "./workspace.css";

type Minor = string | null;
type Rate = {
  id: string;
  name: string;
  kind: "standard" | "promotion" | "targeted_promotion";
  numerator: number;
  denominator: number;
  starts_on: string;
  ends_on: string | null;
  selector: Record<string, string>;
  signup_within_days: number | null;
  priority: number | null;
  reason?: string;
};
type Line = {
  id: string;
  customer_id: string;
  customer_name: string;
  service_id: string;
  eligible_minor: Minor;
  earned_minor: Minor;
  coverage_minor: Minor;
  incremental_minor: Minor;
  rate: Rate | null;
  agreement_id: string | null;
  billing_line_ids: string[];
  billing_obligation_ids?: string[];
  exceptions: Issue[];
};
type Issue = { code?: string; message?: string; next_action?: string };
type Agreement = {
  id: string;
  title: string;
  document_version: string;
  document_status: string;
  document_ref?: DocumentRef;
  effective_from: string;
  effective_to: string | null;
  illustrative: boolean;
  configuration_id: string;
  rates: Rate[];
  guarantees: Record<string, unknown>[];
};
type Comparison = {
  id: string;
  hash: string;
  example_id: string;
  business_date: string;
  hypothetical: boolean;
  baseline: {
    status: string;
    earned_minor: Minor;
    lines: Line[];
    exceptions: Issue[];
  };
  proposed: {
    status: string;
    earned_minor: Minor;
    lines: Line[];
    exceptions: Issue[];
  };
  delta_minor: Minor;
};
type Proposal = {
  id: string;
  hash: string;
  status: string;
  effective_from: string;
  comparison: Comparison | null;
  reviews: {
    role: string;
    decision: string;
    comparison_hash: string;
    document_ref?: DocumentRef;
  }[];
  rates?: Rate[];
};
type DocumentRef = {
  system: string;
  document_id: string;
  version: string;
  status: string;
};
type Billing = {
  obligations: {
    id: string;
    revision: number;
    customer_id: string;
    service_id: string;
    amount_minor: string;
    currency: string;
    service_period_start: string;
    service_period_end: string;
    client_terms_ref: string;
    source: { id: string; revision: number };
    route: string;
  }[];
  invoices: {
    id: string;
    revision: number;
    debtor_id: string;
    amount_minor: string;
    status: string;
    lines: {
      id: string;
      obligation_id: string;
      amount_minor: string;
      account_ids: string[];
      assignment_ids: string[];
    }[];
  }[];
  instructions: {
    id: string;
    revision: number;
    obligation_ids: string[];
    account_ids: string[];
    amount_minor: string;
    status: string;
    execution_status: string | null;
  }[];
  accounting: {
    id: string;
    provider: string;
    commercial_id: string;
    reported_status: string | null;
    applied_minor: Minor;
    ar_minor: Minor;
    recognized_minor: Minor;
    observed_at: string;
    mocked: boolean;
  }[];
};
type Workspace = {
  schema_version: string;
  synthetic: boolean;
  workspace: string;
  business_date: string;
  brokers: { id: string; name: string; practice: string }[];
  selected_broker_id: string;
  earnings: {
    status: string;
    basis: string;
    business_date: string;
    updated_at: string;
    earned_minor: Minor;
    coverage_minor: Minor;
    incremental_minor: Minor;
    guarantee_minor: Minor;
    lines: Line[];
    exceptions: Issue[];
  };
  agreements: Agreement[];
  billing: Billing;
  configuration?: {
    id: string;
    hash: string;
    broker_id: string;
    effective_from: string;
    status: string;
    agreement_id: string;
    document_ref: DocumentRef;
    rates: Rate[];
    guarantees: Record<string, unknown>[];
    allowed_dimensions: Record<string, string[]>;
  };
  proposals?: Proposal[];
};
type RateDraft = {
  id: string;
  name: string;
  kind: Rate["kind"];
  percent: string;
  original_percent?: string;
  original_numerator?: number;
  original_denominator?: number;
  starts_on: string;
  ends_on: string;
  customer_type: string;
  product_type: string;
  signup_within_days: string;
  priority: string;
};
type View =
  | "Earnings"
  | "Agreements"
  | "Advisors"
  | "Commercial terms"
  | "Approvals";
const businessDate = "2026-11-13";
const gql = `query Product($workspace:String!,$brokerId:ID,$businessDate:String){productWorkspace(workspace:$workspace,brokerId:$brokerId,businessDate:$businessDate)}`;
const mutation = `mutation Command($action:Command!,$input:JSON!,$key:String!){workbenchCommand(action:$action,input:$input,idempotencyKey:$key){data errors{code message path}}}`;
function money(value: Minor | undefined) {
  if (value == null) return "Not available";
  const n = BigInt(value),
    a = n < 0n ? -n : n;
  return `${n < 0n ? "−" : ""}$${(a / 100n).toLocaleString("en-US")}.${String(a % 100n).padStart(2, "0")}`;
}
function pct(n: number, d: number) {
  if (!d) return "—";
  const scaled = (BigInt(n) * 1000000n) / BigInt(d);
  const whole = scaled / 10000n;
  const fraction = String(scaled % 10000n)
    .padStart(4, "0")
    .replace(/0+$/, "");
  return `${(BigInt(n) * 1000000n) % BigInt(d) ? "≈" : ""}${whole}${fraction ? `.` + fraction : ""}%`;
}
function pctInput(r: Rate) {
  return pct(r.numerator, r.denominator).replace("%", "").replace("≈", "");
}
function parsePercent(s: string) {
  if (!/^\d{1,3}(?:\.\d{1,4})?$/.test(s)) return null;
  const [whole, part = ""] = s.split(".");
  const basis = BigInt(whole) * 10000n + BigInt(part.padEnd(4, "0"));
  return basis <= 1000000n ? Number(basis) : null;
}
function nice(value: string | null | undefined) {
  if (!value) return "Not available";
  return value.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
}
function kindLabel(kind: Rate["kind"]) {
  return kind === "standard"
    ? "Standard share"
    : kind === "promotion"
      ? "Advisor-wide promotion"
      : "Targeted promotion";
}
function dateLabel(date: string | null) {
  if (!date) return "Ongoing";
  const [y, m, d] = date.split("-");
  return new Date(Number(y), Number(m) - 1, Number(d)).toLocaleDateString(
    "en-US",
    { month: "short", day: "numeric", year: "numeric" },
  );
}
function shiftDate(date: string, days: number) {
  if (!date) return "";
  const shifted = new Date(`${date}T00:00:00Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}
function endDateLabel(date: string | null) {
  return dateLabel(date ? shiftDate(date, -1) : null);
}
function documentVersionLabel(version: string | undefined) {
  return version === "legacy-illustration" ? "Original agreement" : `Version ${version || "—"}`;
}
function draftRate(r: Rate): RateDraft {
  return {
    id: r.id,
    name: r.name,
    kind: r.kind,
    percent: pctInput(r),
    original_percent: pctInput(r),
    original_numerator: r.numerator,
    original_denominator: r.denominator,
    starts_on: r.starts_on,
    ends_on: r.ends_on || "",
    customer_type: r.selector?.customer_type || "",
    product_type: r.selector?.product_type || "",
    signup_within_days: r.signup_within_days?.toString() || "",
    priority: r.priority?.toString() || "",
  };
}
function rateWindow(r: Rate, today: string) {
  return r.starts_on > today
    ? "Upcoming"
    : r.ends_on && r.ends_on <= today
      ? "Historical"
      : "Current";
}
function qualifications(issues: Issue[] | undefined) {
  return issues
    ?.map(
      (i) =>
        i.message || i.next_action || nice(i.code || "Incomplete information"),
    )
    .join(" · ");
}
function Badge({ children }: { children: React.ReactNode }) {
  return <span className="ws-badge">{children}</span>;
}
function RateCard({
  rate,
  today,
  context,
}: {
  rate: Rate;
  today: string;
  context?: string;
}) {
  return (
    <div className="ws-rate">
      <div>
        <div className="ws-rate-top">
          <strong>{rate.name}</strong>
          <Badge>{context || rateWindow(rate, today)}</Badge>
        </div>
        <p>
          {kindLabel(rate.kind)} · {dateLabel(rate.starts_on)} –{" "}
          {endDateLabel(rate.ends_on)}
        </p>
        {(Object.keys(rate.selector || {}).length > 0 ||
          rate.signup_within_days) && (
          <small>
            {Object.entries(rate.selector || {})
              .map(([k, v]) => `${nice(k)}: ${nice(v)}`)
              .join(" · ")}
            {rate.signup_within_days
              ? ` · First ${rate.signup_within_days} days after signup`
              : ""}
            {rate.priority != null ? ` · Priority ${rate.priority}` : ""}
          </small>
        )}
      </div>
      <strong className="ws-rate-value">
        {pct(rate.numerator, rate.denominator)}
      </strong>
    </div>
  );
}
function BillingDetail({ line, billing }: { line: Line; billing: Billing }) {
  const obligations = billing.obligations.filter(
    (o) =>
      (line.billing_obligation_ids || []).includes(o.id) ||
      billing.invoices.some((i) =>
        i.lines.some(
          (l) =>
            line.billing_line_ids.includes(l.id) && l.obligation_id === o.id,
        ),
      ),
  );
  const invoices = billing.invoices.filter((i) =>
    i.lines.some(
      (l) =>
        line.billing_line_ids.includes(l.id) ||
        obligations.some((o) => o.id === l.obligation_id),
    ),
  );
  const instructions = billing.instructions.filter((i) =>
    i.obligation_ids.some((id) => obligations.some((o) => o.id === id)),
  );
  return (
    <div className="ws-lineage">
      <h4>Fee and billing context</h4>
      {!obligations.length && !invoices.length && !instructions.length && (
        <p>Billing details are not available yet.</p>
      )}
      {obligations.map((o) => (
        <div key={o.id}>
          <strong>Service fee · {money(o.amount_minor)}</strong>
          <p>
            {dateLabel(o.service_period_start)} –{" "}
            {endDateLabel(o.service_period_end)} · {nice(o.route)}
          </p>
          <details>
            <summary>View source details</summary>
            <small>
              Fee {o.id} v{o.revision} · Client terms {o.client_terms_ref} ·
              Source {o.source.id} v{o.source.revision}
            </small>
          </details>
        </div>
      ))}
      {invoices.map((i) => (
        <div key={i.id}>
          <strong>Invoice · {money(i.amount_minor)}</strong>
          <p>
            Billed to {line.customer_name}
          </p>
          <details>
            <summary>Invoice details</summary>
            <small>
              {i.id} v{i.revision} ·{" "}
              {i.lines
                .map(
                  (l) =>
                    `Line ${l.id}, accounts ${l.account_ids.join(", ")}, assignments ${l.assignment_ids.join(", ")}`,
                )
                .join("; ")}
            </small>
          </details>
        </div>
      ))}
      {instructions.map((i) => (
        <div key={i.id}>
          <strong>Custodial instruction · {money(i.amount_minor)}</strong>
          <p>
            {i.execution_status ? nice(i.execution_status) : "Awaiting execution details"}
          </p>
          <details>
            <summary>Instruction details</summary>
            <small>
              {i.id} v{i.revision} · Accounts {i.account_ids.join(", ")}
            </small>
          </details>
        </div>
      ))}
    </div>
  );
}
function Earnings({ data, internal = false }: { data: Workspace; internal?: boolean }) {
  const e = data.earnings;
  return (
    <>
      <div className="ws-heading">
        <div>
          {internal ? <><span className="ws-eyebrow">ADVISOR EARNINGS</span><h2>{data.brokers.find(b => b.id === data.selected_broker_id)?.name || "Advisor"} · Current earnings</h2></> : <><span className="ws-eyebrow">YOUR COMPENSATION</span><h1>Your earnings</h1></>}
          <p>
            Based on available customer fees through{" "}
            {dateLabel(e.business_date)}. Updated{" "}
            {new Date(e.updated_at).toLocaleString("en-US", {
              timeZone: "America/New_York",
              month: "short",
              day: "numeric",
              hour: "numeric",
              minute: "2-digit",
            })}{" "}
            ET.
          </p>
        </div>
        {e.status !== "completed" && <Badge>{nice(e.status)}</Badge>}
      </div>
      <div className="ws-hero">
        <div>
          <span>Estimated payment after coverage</span>
          <strong>{money(e.incremental_minor)}</strong>
          <p>
            Earned compensation less coverage.
          </p>
          {e.incremental_minor == null && (
            <small>
              Available when the required earnings and coverage are known.
            </small>
          )}
        </div>
        <div className="ws-hero-side">
          <div>
            <span>Earned compensation</span>
            <strong>{money(e.earned_minor)}</strong>
          </div>
          <div>
            <span>Coverage</span>
            <strong>{money(e.coverage_minor)}</strong>
          </div>
          {e.guarantee_minor != null &&
            data.agreements.some((a) => a.guarantees.length > 0) && (
              <div>
                <span>Provisional guarantee</span>
                <strong>{money(e.guarantee_minor)}</strong>
              </div>
            )}
        </div>
      </div>
      {qualifications(e.exceptions) && (
        <p className="ws-warning">{qualifications(e.exceptions)}</p>
      )}
      <section className="ws-panel">
        <div className="ws-panel-head">
          <div>
            <h2>Customer earnings</h2>
          </div>
          <span>
            {new Set(e.lines.map((line) => line.customer_id)).size}{" "}
            {new Set(e.lines.map((line) => line.customer_id)).size === 1
              ? "customer"
              : "customers"}
          </span>
        </div>
        {e.lines.length === 0 ? (
          <p className="ws-empty">
            No customer fees are available for this date.
          </p>
        ) : (
          <div className="ws-customer-list">
            {e.lines.map((line) => (
              <details className="ws-customer" key={line.id}>
                <summary>
                  <span className="ws-avatar">
                    {line.customer_name?.charAt(0) || "C"}
                  </span>
                  <span className="ws-customer-name">
                    <strong>{line.customer_name}</strong>
                    <small>{line.rate?.name || "Share not available"}</small>
                  </span>
                  <span className="ws-customer-amount">
                    <strong>{money(line.earned_minor)}</strong>
                    <small>Earned</small>
                  </span>
                  <span className="ws-chevron" aria-hidden="true">
                    ⌄
                  </span>
                </summary>
                <div className="ws-customer-detail">
                  <div className="ws-detail-metrics">
                    <div>
                      <span>Eligible fee</span>
                      <strong>{money(line.eligible_minor)}</strong>
                    </div>
                    <div>
                      <span>Selected share</span>
                      <strong>
                        {line.rate
                          ? pct(line.rate.numerator, line.rate.denominator)
                          : "Not available"}
                      </strong>
                    </div>
                    <div>
                      <span>Coverage</span>
                      <strong>{money(line.coverage_minor)}</strong>
                    </div>
                    <div>
                      <span>Estimated incremental</span>
                      <strong>{money(line.incremental_minor)}</strong>
                    </div>
                  </div>
                  {qualifications(line.exceptions) && (
                    <p className="ws-warning">
                      {qualifications(line.exceptions)}
                    </p>
                  )}
                  <p>
                    {line.rate
                      ? `${line.rate.name} applies to this fee. ${line.rate.kind === "targeted_promotion" ? "This eligible promotion replaces the standard and advisor-wide shares." : line.rate.kind === "promotion" ? "This advisor-wide promotion replaces the standard share." : "The standard share applies."}`
                      : "The applicable share could not be determined."}
                  </p>
                  {line.rate &&
                    data.agreements
                      .flatMap((a) => a.rates)
                      .filter((r) => r.id === line.rate?.id)
                      .slice(0, 1)
                      .map((r) => (
                        <p key={r.id}>
                          Effective {dateLabel(r.starts_on)} –{" "}
                          {endDateLabel(r.ends_on)}
                          {Object.keys(r.selector || {}).length
                            ? ` · ${Object.entries(r.selector)
                                .map(([k, v]) => `${nice(k)}: ${nice(v)}`)
                                .join(" · ")}`
                            : ""}
                          {r.signup_within_days
                            ? ` · First ${r.signup_within_days} days after signup`
                            : ""}
                        </p>
                      ))}
                  <details><summary>Calculation details</summary><small>
                    Service {line.service_id} · Agreement{" "}
                    {line.agreement_id || "not available"} · Observation{" "}
                    {line.id}
                  </small></details>
                  <BillingDetail line={line} billing={data.billing} />
                </div>
              </details>
            ))}
          </div>
        )}
      </section>
    </>
  );
}
function Agreements({ data }: { data: Workspace }) {
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">YOUR TERMS</span>
          <h1>Agreements</h1>
          <p>Understand the terms used to explain your earnings.</p>
        </div>
      </div>
      {data.agreements.length ? (
        data.agreements.map((a) => (
          <section
            className="ws-panel ws-agreement"
            key={`${a.id}-${a.configuration_id}`}
          >
            <div className="ws-panel-head">
              <div>
                <span className="ws-eyebrow">AGREEMENT</span>
                <h2>{nice(a.title.replace(/^Illustrative /i, ""))}</h2>
                <p>
                  Effective {dateLabel(a.effective_from)} –{" "}
                  {endDateLabel(a.effective_to)}
                </p>
              </div>
              <Badge>
                {a.effective_from > data.business_date
                  ? "Approved upcoming"
                  : a.effective_to && a.effective_to <= data.business_date
                    ? "Historical"
                    : "Current"}
              </Badge>
            </div>
            <div className="ws-document">
              <span className="ws-document-icon">▤</span>
              <div>
                <strong>
                  Agreement document
                </strong>
                <p>
                  {documentVersionLabel(a.document_version)}
                </p>
                <details><summary>Document details</summary><small>
                  {a.document_ref?.document_id || a.id}
                </small></details>
              </div>
            </div>
            <h3>Compensation terms</h3>
            <div className="ws-rate-list">
              {a.rates.map((r) => (
                <RateCard
                  key={r.id}
                  rate={r}
                  today={data.business_date}
                  context={
                    a.effective_from > data.business_date
                      ? "Approved upcoming"
                      : a.effective_to && a.effective_to <= data.business_date
                        ? "Historical"
                        : undefined
                  }
                />
              ))}
            </div>
            {a.guarantees.length > 0 && (
              <div className="ws-guarantee">
                <strong>Guarantee terms</strong>
                {a.guarantees.map((g, i) => (
                  <p key={i}>
                    Provisional guarantee{" "}
                    {money(
                      g.threshold != null || g.amount_minor != null
                        ? String(g.threshold ?? g.amount_minor)
                        : null,
                    )}
                    {g.metric ? ` · ${nice(String(g.metric))}` : ""}
                    {g.period && typeof g.period === "object"
                      ? ` · ${dateLabel(String((g.period as Record<string, string>).start))} to ${endDateLabel(String((g.period as Record<string, string>).end_exclusive))}`
                      : ""}
                  </p>
                ))}
              </div>
            )}
          </section>
        ))
      ) : (
        <div className="ws-empty">No agreement is available yet.</div>
      )}
    </>
  );
}
function Advisors({
  data,
  onSelect,
}: {
  data: Workspace;
  onSelect: (id: string) => void;
}) {
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL WORKSPACE</span>
          <h1>Advisors</h1>
          <p>Explore the people and terms behind the numbers.</p>
        </div>
      </div>
      <section className="ws-panel">
        <div className="ws-panel-head">
          <h2>Advisor directory</h2>
          <span>{data.brokers.length} advisors</span>
        </div>
        <div className="ws-customer-list">
          {data.brokers.map((b) => (
            <button
              className="ws-advisor"
              key={b.id}
              onClick={() => onSelect(b.id)}
            >
              <span className="ws-avatar">{b.name.charAt(0)}</span>
              <span>
                <strong>{b.name}</strong>
                <small>{b.practice}</small>
              </span>
              <span className="ws-advisor-link">View commercial terms</span>
            </button>
          ))}
        </div>
      </section>
    </>
  );
}
function Terms({
  data,
  busy,
  onSave,
}: {
  data: Workspace;
  busy: boolean;
  onSave: (input: unknown) => Promise<unknown>;
}) {
  const config = data.configuration;
  const [rates, setRates] = useState<RateDraft[]>([]),
    [effective, setEffective] = useState(""),
    [reason, setReason] = useState("");
  useEffect(() => {
    setRates(config?.rates.map(draftRate) || []);
    setEffective(data.business_date);
    setReason("");
  }, [config?.id, data.business_date]);
  if (!config)
    return (
      <div className="ws-empty">
        Commercial terms are not available for this advisor.
      </div>
    );
  const update = (i: number, key: keyof RateDraft, value: string) =>
    setRates((old) =>
      old.map((r, j) => (i === j ? { ...r, [key]: value } : r)),
    );
  const valid =
    rates.length > 0 &&
    rates.every(
      (r) =>
        r.name.trim() &&
        r.starts_on &&
        parsePercent(r.percent) !== null &&
        (!r.ends_on || r.ends_on > r.starts_on) &&
        (!r.signup_within_days ||
          (/^\d+$/.test(r.signup_within_days) &&
            Number(r.signup_within_days) >= 1 &&
            Number(r.signup_within_days) <= 365)) &&
        (!r.priority || /^\d+$/.test(r.priority)),
    );
  const submit = async () => {
    if (!valid) return;
    const payload = rates.map((r) => ({
      id: r.id,
      name: r.name.trim(),
      kind: r.kind,
      numerator:
        r.percent === r.original_percent
          ? r.original_numerator
          : parsePercent(r.percent),
      denominator:
        r.percent === r.original_percent ? r.original_denominator : 1000000,
      starts_on: r.starts_on,
      ends_on: r.ends_on || null,
      selector: {
        ...(r.customer_type ? { customer_type: r.customer_type } : {}),
        ...(r.product_type ? { product_type: r.product_type } : {}),
      },
      signup_within_days: r.signup_within_days
        ? Number(r.signup_within_days)
        : null,
      priority: r.priority ? Number(r.priority) : null,
    }));
    await onSave({
      broker_id: config.broker_id,
      base_configuration_id: config.id,
      expected_base_hash: config.hash,
      effective_from: effective,
      rates: payload,
      reason: reason.trim(),
    });
  };
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">
            INTERNAL ·{" "}
            {data.brokers
              .find((b) => b.id === data.selected_broker_id)
              ?.name?.toUpperCase() || "ADVISOR"}
          </span>
          <h1>Commercial terms</h1>
          <p>
            Review the current schedule and prepare a change for comparison.
          </p>
        </div>
        <Badge>
          {config.status === "legacy_active"
            ? "Current terms"
            : nice(config.status)}
        </Badge>
      </div>
      <details className="ws-panel ws-padded"><summary>Current earnings context</summary><Earnings data={data} internal /></details>
      <section className="ws-panel ws-padded">
        <div className="ws-panel-head">
          <div>
            <h2>Current agreement terms</h2>
            <p>Advisor compensation is separate from client fee terms.</p>
          </div>
        </div>
        <div className="ws-rate-list">
          {config.rates.map((r) => (
            <RateCard key={r.id} rate={r} today={data.business_date} />
          ))}
        </div>
        <div className="ws-document compact">
          <span className="ws-document-icon">▤</span>
          <div>
            <strong>Agreement document</strong>
            <p>{documentVersionLabel(config.document_ref?.version)}</p>
            <details><summary>Document details</summary><small>
              {config.agreement_id} · {config.document_ref?.document_id}
            </small></details>
          </div>
        </div>
      </section>
      <section className="ws-panel ws-padded">
        <div className="ws-panel-head">
          <div>
            <h2>Prepare a terms proposal</h2>
            <p>
              A proposal is a draft. Comparing, review, and scheduling are
              separate steps.
            </p>
          </div>
        </div>
        <div className="ws-form-grid">
          <label>
            Proposed effective date
            <input
              type="date"
              value={effective}
              onChange={(e) => setEffective(e.target.value)}
            />
          </label>
          <label>
            Reason for the change
            <input
              maxLength={300}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Describe the business decision"
            />
          </label>
        </div>
        <div className="ws-edit-list">
          {rates.map((r, i) => (
            <fieldset className="ws-rate-editor" key={`${r.id}-${i}`}>
              <legend>{r.name || "New rate"}</legend>
              <div className="ws-form-grid">
                <label>
                  Friendly name
                  <input
                    value={r.name}
                    onChange={(e) => update(i, "name", e.target.value)}
                  />
                </label>
                <label>
                  Type
                  <select
                    value={r.kind}
                    onChange={(e) => {
                      const kind = e.target.value as Rate["kind"];
                      setRates((old) =>
                        old.map((item, j) =>
                          j === i
                            ? {
                                ...item,
                                kind,
                                ...(kind !== "targeted_promotion"
                                  ? {
                                      customer_type: "",
                                      product_type: "",
                                      signup_within_days: "",
                                      priority: "",
                                    }
                                  : {}),
                              }
                            : item,
                        ),
                      );
                    }}
                  >
                    <option value="standard">Standard share</option>
                    <option value="promotion">Advisor-wide promotion</option>
                    <option value="targeted_promotion">
                      Targeted promotion
                    </option>
                  </select>
                </label>
                <label>
                  Share (%)
                  <input
                    inputMode="decimal"
                    value={r.percent}
                    onChange={(e) => update(i, "percent", e.target.value)}
                    placeholder="e.g. 70.00"
                  />
                </label>
                <label>
                  Starts on
                  <input
                    type="date"
                    value={r.starts_on}
                    onChange={(e) => update(i, "starts_on", e.target.value)}
                  />
                </label>
                <label>
                  Last day (optional)
                  <input
                    type="date"
                    value={shiftDate(r.ends_on, -1)}
                    onChange={(e) => update(i, "ends_on", shiftDate(e.target.value, 1))}
                  />
                </label>
                {r.kind === "targeted_promotion" && (
                  <>
                    <label>
                      Customer type (optional)
                      <select
                        value={r.customer_type}
                        onChange={(e) =>
                          update(i, "customer_type", e.target.value)
                        }
                      >
                        <option value="">Any customer type</option>
                        {(config.allowed_dimensions?.customer_type || []).map(
                          (v) => (
                            <option key={v} value={v}>
                              {nice(v)}
                            </option>
                          ),
                        )}
                      </select>
                    </label>
                    <label>
                      Product type (optional)
                      <select
                        value={r.product_type}
                        onChange={(e) =>
                          update(i, "product_type", e.target.value)
                        }
                      >
                        <option value="">Any product type</option>
                        {(config.allowed_dimensions?.product_type || []).map(
                          (v) => (
                            <option key={v} value={v}>
                              {nice(v)}
                            </option>
                          ),
                        )}
                      </select>
                    </label>
                    <label>
                      Within days of signup (optional)
                      <input
                        inputMode="numeric"
                        value={r.signup_within_days}
                        onChange={(e) =>
                          update(i, "signup_within_days", e.target.value)
                        }
                        placeholder="1–365"
                      />
                    </label>
                    <label>
                      Priority (optional)
                      <input
                        inputMode="numeric"
                        value={r.priority}
                        onChange={(e) => update(i, "priority", e.target.value)}
                      />
                    </label>
                  </>
                )}
              </div>
              <button
                className="ws-link"
                type="button"
                onClick={() => setRates((old) => old.filter((_, j) => j !== i))}
              >
                Remove this rate
              </button>
            </fieldset>
          ))}
        </div>
        <button
          className="ws-secondary"
          type="button"
          onClick={() =>
            setRates((old) => [
              ...old,
              {
                id: `rate-${crypto.randomUUID()}`,
                name: "",
                kind: "targeted_promotion",
                percent: "",
                starts_on: effective,
                ends_on: "",
                customer_type: "",
                product_type: "",
                signup_within_days: "",
                priority: "",
              },
            ])
          }
        >
          + Add rate
        </button>
        <div className="ws-form-footer">
          <p>
            The most specific eligible promotion applies. Shares are not combined.
          </p>
          <button
            className="ws-primary"
            disabled={busy || !valid || !effective || reason.trim().length < 3}
            onClick={submit}
          >
            Save proposal
          </button>
        </div>
      </section>
    </>
  );
}
function Approvals({
  data,
  busy,
  onCommand,
}: {
  data: Workspace;
  busy: boolean;
  onCommand: (
    action: string,
    input: unknown,
    role?: string,
  ) => Promise<unknown>;
}) {
  const [example, setExample] = useState("current_book"),
    [docId, setDocId] = useState("mock-amendment"),
    [version, setVersion] = useState("v1");
  const proposals = data.proposals || [];
  return (
    <>
      <div className="ws-heading">
        <div>
          <span className="ws-eyebrow">INTERNAL WORKSPACE</span>
          <h1>Approvals</h1>
          <p>Compare and review each proposal before it is scheduled.</p>
        </div>
      </div>
      {!proposals.length && (
        <div className="ws-empty">
          No proposals yet. Prepare one in Commercial terms to get started.
        </div>
      )}
      {proposals.map((p) => {
        const c = p.comparison,
          reviewed = (role: string) =>
            p.reviews?.some(
              (r) =>
                r.role?.toLowerCase() === role &&
                r.decision === "approved_for_demo" &&
                r.comparison_hash === c?.hash &&
                r.document_ref?.document_id === docId.trim() &&
                r.document_ref?.version === version.trim(),
            );
        return (
          <section className="ws-panel ws-padded ws-proposal" key={p.id}>
            <div className="ws-panel-head">
              <div>
                <span className="ws-eyebrow">PROPOSED TERMS</span>
                <h2>Change effective {dateLabel(p.effective_from)}</h2>
              </div>
              <Badge>{nice(p.status)}</Badge>
            </div>
            <div className="ws-proposal-copy">
              <strong>Change summary</strong>
              <p>
                Update the advisor compensation schedule effective{" "}
                {dateLabel(p.effective_from)}.
              </p>
            </div>
            <div className="ws-rate-list">
              {p.rates?.map((r) => (
                <RateCard
                  key={r.id}
                  rate={r}
                  today={data.business_date}
                  context={p.status === "scheduled" ? "Scheduled" : "Proposed"}
                />
              ))}
            </div>
            <div className="ws-form-grid">
              <label>
                Comparison scenario
                <select
                  value={example}
                  onChange={(e) => setExample(e.target.value)}
                >
                  <option value="current_book">Current book</option>
                  <option value="future_signup_example">
                    New customer scenario
                  </option>
                </select>
              </label>
              <div className="ws-align-end">
                <button
                  className="ws-secondary"
                  disabled={busy || p.status === "scheduled"}
                  onClick={() =>
                    onCommand("COMPARE_TERMS_PROPOSAL", {
                      proposal_id: p.id,
                      expected_hash: p.hash,
                      example_id: example,
                    })
                  }
                >
                  Compare terms
                </button>
              </div>
            </div>
            {c && (
              <div className="ws-comparison">
                <div className="ws-panel-head">
                  <div>
                    <h3>
                      {c.example_id === "future_signup_example"
                        ? "New customer scenario"
                        : c.hypothetical
                          ? "Current book scenario"
                          : "Current book comparison"}
                    </h3>
                    <p>
                      As of {dateLabel(c.business_date)} ·{" "}
                      {nice(c.proposed.status)}
                    </p>
                  </div>
                </div>
                {c.hypothetical && (
                  <p className="ws-footnote">
                    Projected impact only. Current earnings are unchanged.
                  </p>
                )}
                <div className="ws-compare-grid">
                  <div>
                    <span>Current terms</span>
                    <strong>{money(c.baseline.earned_minor)}</strong>
                  </div>
                  <div>
                    <span>Proposed terms</span>
                    <strong>{money(c.proposed.earned_minor)}</strong>
                  </div>
                  <div>
                    <span>Change</span>
                    <strong>{money(c.delta_minor)}</strong>
                  </div>
                </div>
                {qualifications([
                  ...(c.baseline.exceptions || []),
                  ...(c.proposed.exceptions || []),
                ]) && (
                  <p className="ws-warning">
                    {qualifications([
                      ...(c.baseline.exceptions || []),
                      ...(c.proposed.exceptions || []),
                    ])}
                  </p>
                )}
                <details>
                  <summary>Comparison details</summary>
                  {c.proposed.lines?.map((l) => (
                    <p key={l.id}>
                      {l.customer_name}: {money(l.earned_minor)} ·{" "}
                      {l.rate?.name || "Share unavailable"}
                    </p>
                  ))}
                </details>
              </div>
            )}
            <div className="ws-review-block">
              <div>
                <h3>Document review</h3>
                <p>
                  Legal and Finance review the terms, comparison and document version together.
                </p>
              </div>
              <details><summary>Document details</summary><div className="ws-form-grid">
                <label>
                  Document ID
                  <input
                    value={docId}
                    onChange={(e) => setDocId(e.target.value)}
                  />
                </label>
                <label>
                  Version
                  <input
                    value={version}
                    onChange={(e) => setVersion(e.target.value)}
                  />
                </label>
              </div></details>
              <div className="ws-review-actions">
                {["legal", "finance"].map((role) => (
                  <div key={role}>
                    <strong>{nice(role)}</strong>
                    <span>
                      {reviewed(role) ? "Reviewed" : "Review needed"}
                    </span>
                    <button
                      className="ws-secondary"
                      disabled={
                        busy ||
                        !c ||
                        c.proposed.status !== "completed" ||
                        c.baseline.status !== "completed" ||
                        !docId.trim() ||
                        !version.trim() ||
                        p.status === "scheduled" ||
                        reviewed(role)
                      }
                      onClick={() =>
                        onCommand(
                          "REVIEW_TERMS_PROPOSAL",
                          {
                            proposal_id: p.id,
                            expected_hash: p.hash,
                            comparison_hash: c?.hash,
                            document_ref: {
                              system: "mock_clm",
                              document_id: docId.trim(),
                              version: version.trim(),
                              status: "reviewed_for_demo",
                            },
                            decision: "approved_for_demo",
                          },
                          role,
                        )
                      }
                    >
                      Approve as {nice(role)}
                    </button>
                  </div>
                ))}
              </div>
              <button
                className="ws-primary"
                disabled={
                  busy ||
                  !c ||
                  !reviewed("legal") ||
                  !reviewed("finance") ||
                  p.status === "scheduled"
                }
                onClick={() =>
                  onCommand(
                    "SCHEDULE_TERMS_PROPOSAL",
                    {
                      proposal_id: p.id,
                      expected_hash: p.hash,
                      comparison_hash: c?.hash,
                    },
                    "finance",
                  )
                }
              >
                Schedule reviewed terms
              </button>
            </div>
          </section>
        );
      })}
    </>
  );
}
export default function Page() {
  const [experience, setExperience] = useState<"broker" | "internal">("broker"),
    [view, setView] = useState<View>("Earnings"),
    [broker, setBroker] = useState("broker-alex"),
    [data, setData] = useState<Workspace | null>(null),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  const request = useCallback(
    async (query: string, variables: unknown, role: string) => {
      const response = await fetch("/api/graphql", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Demo-Role": role },
        body: JSON.stringify({ query, variables }),
      });
      const body = await response.json();
      if (!response.ok || body.errors?.length)
        throw new Error(
          body.errors?.[0]?.message ||
            body.error ||
            "Unable to connect. Please try again.",
        );
      return body.data;
    },
    [],
  );
  const load = useCallback(async () => {
    const r = await request(
      gql,
      {
        workspace: experience,
        brokerId: experience === "broker" ? "broker-alex" : broker,
        businessDate,
      },
      experience === "broker" ? "advisor" : "operator",
    );
    setData(r.productWorkspace);
  }, [request, experience, broker]);
  useEffect(() => {
    let active = true;
    setData(null);
    setError("");
    request(
      gql,
      {
        workspace: experience,
        brokerId: experience === "broker" ? "broker-alex" : broker,
        businessDate,
      },
      experience === "broker" ? "advisor" : "operator",
    )
      .then((r) => {
        if (active) setData(r.productWorkspace);
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [request, experience, broker]);
  async function command(action: string, input: unknown, role = "operator") {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const r = await request(
        mutation,
        { action, input, key: crypto.randomUUID() },
        role,
      );
      if (r.workbenchCommand.errors?.length)
        throw new Error(
          r.workbenchCommand.errors
            .map((e: Issue) => e.message || e.code)
            .join("; "),
        );
      await load();
      setNotice(
        action === "SAVE_TERMS_PROPOSAL"
          ? "Proposal saved. Open Approvals to compare it."
          : action === "COMPARE_TERMS_PROPOSAL"
            ? "Comparison ready for review."
            : action === "REVIEW_TERMS_PROPOSAL"
              ? `${nice(role)} review recorded.`
              : "Reviewed terms scheduled.",
      );
      return r.workbenchCommand.data;
    } catch (e) {
      setError((e as Error).message);
      return null;
    } finally {
      setBusy(false);
    }
  }
  const changeExperience = (next: "broker" | "internal") => {
    setExperience(next);
    setView(next === "broker" ? "Earnings" : "Advisors");
    setError("");
    setNotice("");
  };
  const nav: View[] =
    experience === "broker"
      ? ["Earnings", "Agreements"]
      : ["Advisors", "Commercial terms", "Approvals"];
  return (
    <div className="ws-app">
      <aside className="ws-sidebar">
        <a className="ws-skip" href="#workspace-main">
          Skip to content
        </a>
        <div className="ws-brand">
          <img src="/savvy/logo.svg" alt="Savvy" width="112" height="39" />
          <span>ADVISOR WORKSPACE</span>
        </div>
        <div className="ws-experience">
          <span>WORKSPACE</span>
          <div>
            <button
              aria-pressed={experience === "broker"}
              onClick={() => changeExperience("broker")}
            >
              Broker
            </button>
            <button
              aria-pressed={experience === "internal"}
              onClick={() => changeExperience("internal")}
            >
              Internal
            </button>
          </div>
        </div>
        <div className="ws-sidebar-label">
          {experience === "broker" ? "YOUR WORKSPACE" : "TEAM WORKSPACE"}
        </div>
        <nav aria-label={`${experience} navigation`}>
          {nav.map((n, i) => (
            <button
              key={n}
              aria-current={view === n ? "page" : undefined}
              onClick={() => {
                setView(n);
                setNotice("");
                setError("");
              }}
            >
              <span aria-hidden="true">
                {experience === "broker" ? ["◫", "▤"][i] : ["◉", "≋", "✓"][i]}
              </span>
              {n}
            </button>
          ))}
        </nav>
      </aside>
      <div className="ws-main-wrap">
        <header className="ws-topbar">
          <div>
            {experience === "broker"
              ? "Broker workspace"
              : "Internal workspace"}{" "}
            <span>/</span> {view}
          </div>
          {experience === "internal" && data && view !== "Advisors" && (
            <label>
              Advisor{" "}
              <select
                value={broker}
                onChange={(e) => setBroker(e.target.value)}
              >
                {data.brokers.map((b) => (
                  <option value={b.id} key={b.id}>
                    {b.name}
                  </option>
                ))}
              </select>
            </label>
          )}
        </header>
        <main className="ws-main" id="workspace-main">
          {error && (
            <div role="alert" className="ws-alert">
              {error}
              <button aria-label="Dismiss error" onClick={() => setError("")}>
                ×
              </button>
            </div>
          )}
          {notice && (
            <div role="status" className="ws-notice">
              {notice}
              <button
                aria-label="Dismiss message"
                onClick={() => setNotice("")}
              >
                ×
              </button>
            </div>
          )}
          {!data ? (
            <div className="ws-empty">
              {error ? (
                <button
                  className="ws-secondary"
                  onClick={() => load().catch((e) => setError(e.message))}
                >
                  Try again
                </button>
              ) : (
                "Opening your workspace…"
              )}
            </div>
          ) : (
            <>
              {view === "Earnings" && <Earnings data={data} />}{" "}
              {view === "Agreements" && <Agreements data={data} />}{" "}
              {view === "Advisors" && (
                <Advisors
                  data={data}
                  onSelect={(id) => {
                    setBroker(id);
                    setView("Commercial terms");
                  }}
                />
              )}{" "}
              {view === "Commercial terms" && (
                <Terms
                  data={data}
                  busy={busy}
                  onSave={async (input) => {
                    const result = await command("SAVE_TERMS_PROPOSAL", input);
                    if (result) setView("Approvals");
                    return result;
                  }}
                />
              )}{" "}
              {view === "Approvals" && (
                <Approvals data={data} busy={busy} onCommand={command} />
              )}
            </>
          )}
        </main>
      </div>
    </div>
  );
}
