"use client";
import { useEffect, useState } from "react";
type Minor = string | null;
type Application = {
  id: string;
  receipt_id: string;
  minor_units: string;
  status: string;
  recorded_at: string;
  reason?: string;
  reversal_of_id: string | null;
};
type Exception = {
  code: string;
  owner: string;
  next_action: string;
  evidence_ids: string[];
};
type Close = {
  id: string;
  manifest_hash: string;
  closed_at: string;
  reason: string;
};
type Review = {
  mode: "current" | "frozen";
  manifest_hash: string;
  knowledge_cutoff: string;
  close: Close | null;
  closes: Close[];
  invoices: {
    id: string;
    charge_id: string;
    customer_id: string;
    amount_minor: string;
    applied_minor: Minor;
    open_minor: Minor;
    application_status: string;
    applications: Application[];
  }[];
  bank_batches: {
    id: string;
    gross_minor: string;
    fee_minor: string;
    net_minor: string;
    receipt_ids: string[];
    status: string;
    recorded_at: string;
    reversal?: { id: string; recorded_at: string; reason: string } | null;
  }[];
  totals: {
    invoice_amount_minor: Minor;
    invoice_applied_minor: Minor;
    invoice_open_minor: Minor;
    bank_gross_minor: Minor;
    bank_fee_minor: Minor;
    bank_net_minor: Minor;
    recognized_revenue_minor: Minor;
  };
  exceptions: Exception[];
  late_exceptions?: Exception[];
  later_evidence: {
    id: string;
    kind: string;
    recorded_at: string;
    reason: string;
  }[];
};
type ReceiptOption = {
  id: string;
  customer: string;
  customer_name: string;
  amount_minor: string;
};
type Props = {
  customers: { id: string; name: string }[];
  receipts: ReceiptOption[];
  role: string;
  busy: boolean;
  refresh: number;
  request: (query: string, variables?: unknown) => Promise<any>;
  command: (action: string, input: unknown) => Promise<unknown>;
  formatMoney: (v: Minor) => string;
};
const exceptionTitles: Record<string, string> = {
  INVOICE_APPLICATION_UNKNOWN: "Invoice application evidence needed",
  BANK_SETTLEMENT_UNKNOWN: "Bank settlement evidence needed",
  RECOGNITION_UNKNOWN: "Revenue recognition is unknown",
  RECEIPT_APPLICATION_CONFLICT: "Receipt and invoice application conflict",
  RECEIPT_BANK_CONFLICT: "Receipt and bank batch conflict",
  LATE_EVIDENCE: "Evidence recorded after this review",
};
const query =
  "query Reconciliation($start:String!,$end:String!,$closeId:ID){reconciliation(periodStart:$start,periodEndExclusive:$end,closeId:$closeId)}";
export default function ReconciliationDesk({
  customers,
  receipts: receiptOptions,
  role,
  busy,
  refresh,
  request,
  command,
  formatMoney,
}: Props) {
  const [start, setStart] = useState("2026-11-01"),
    [end, setEnd] = useState("2026-12-01"),
    [period, setPeriod] = useState({ start: "2026-11-01", end: "2026-12-01" }),
    [closeId, setCloseId] = useState("");
  const [review, setReview] = useState<Review | null>(null),
    [closes, setCloses] = useState<Close[]>([]),
    [error, setError] = useState(""),
    [retry, setRetry] = useState(0);
  const [reason, setReason] = useState(""),
    [date, setDate] = useState("2026-11-13"),
    [invoice, setInvoice] = useState(""),
    [receipt, setReceipt] = useState(""),
    [amount, setAmount] = useState("");
  const [selectedReceipts, setSelectedReceipts] = useState<string[]>([]),
    [fee, setFee] = useState("");
  useEffect(() => {
    let active = true;
    setReview(null);
    setError("");
    Promise.all([
      request(query, { ...period, closeId: closeId || null }),
      ...(closeId ? [request(query, { ...period, closeId: null })] : []),
    ])
      .then(([r, current]) => {
        if (active) {
          setReview(r.reconciliation);
          setCloses((current || r).reconciliation.closes);
        }
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [request, period, closeId, refresh, retry]);
  const canWrite =
    role === "finance" &&
    review?.mode === "current" &&
    !busy &&
    reason.trim().length >= 3 &&
    !!date;
  const common = { business_date: date, reason: reason.trim() };
  const cents = (value: string): string | null => {
    if (!/^\d{1,13}(?:\.\d{1,2})?$/.test(value)) return null;
    const [whole, fraction = ""] = value.split(".");
    return (BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"))).toString();
  };
  const applicationCents = cents(amount),
    feeCents = cents(fee);
  const grossCents = selectedReceipts.reduce(
    (total, id) =>
      total +
      BigInt(receiptOptions.find((r) => r.id === id)?.amount_minor || "0"),
    0n,
  );
  const netCents =
    feeCents !== null && BigInt(feeCents) <= grossCents
      ? (grossCents - BigInt(feeCents)).toString()
      : null;
  const exceptions = (items: Exception[]) =>
    items.map((x, i) => (
      <div className="recon-exception" key={`${x.code}-${i}`}>
        <strong>
          {exceptionTitles[x.code] || x.code.replaceAll("_", " ").toLowerCase()}
        </strong>
        <p>{x.next_action}</p>
        <small>
          Code: {x.code} · Owner: {x.owner} · Evidence:{" "}
          {x.evidence_ids.join(", ") || "None supplied"}
        </small>
      </div>
    ));
  return (
    <div className="reconciliation">
      <div className="note wide">
        <strong>Independent evidence, one review</strong>
        <p>
          Invoice applications and bank batches are supplied separately from
          operational cash matches. This synthetic review does not post
          accounting entries, move money, or establish recognized revenue.
        </p>
      </div>
      <section className="panel padded">
        <div className="panel-heading">
          <div>
            <h2>Review period</h2>
            <p>
              Invoices follow their charge’s service period; bank batches follow
              their business date. The end date is exclusive.
            </p>
          </div>
          <span className="pill gray">Synthetic · USD</span>
        </div>
        <form
          className="recon-controls"
          onSubmit={(e) => {
            e.preventDefault();
            setCloseId("");
            setPeriod({ start, end });
          }}
        >
          <label className="field">
            Start date
            <input
              type="date"
              required
              value={start}
              onChange={(e) => setStart(e.target.value)}
            />
          </label>
          <label className="field">
            End date (exclusive)
            <input
              type="date"
              required
              value={end}
              onChange={(e) => setEnd(e.target.value)}
            />
          </label>
          <button
            className="secondary"
            disabled={!start || !end || start >= end}
          >
            View period
          </button>
        </form>
        {review && (
          <div className="recon-meta">
            <label>
              Review version{" "}
              <select
                value={closeId}
                onChange={(e) => setCloseId(e.target.value)}
              >
                <option value="">Current evidence</option>
                {closes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.id} · {c.closed_at}
                  </option>
                ))}
              </select>
            </label>
            <p>
              {review.mode === "frozen"
                ? `Saved review ${review.close?.id} · ${review.close?.reason}`
                : "Current evidence"}{" "}
              · Knowledge cutoff {review.knowledge_cutoff}
            </p>
            <p className="recon-hash">Manifest: {review.manifest_hash}</p>
          </div>
        )}
      </section>
      {error && (
        <div className="alert error" role="alert">
          {error}{" "}
          <button className="secondary" onClick={() => setRetry(retry + 1)}>
            Try again
          </button>
        </div>
      )}
      {!review && !error && (
        <div className="empty">Loading reconciliation evidence…</div>
      )}
      {review && (
        <>
          {review.mode === "frozen" && (
            <div className="note wide">
              <strong>Saved review is read-only</strong>
              <p>
                This is the evidence captured at review time. Later changes are
                listed separately below. Select current evidence to record a
                change.
              </p>
            </div>
          )}
          <section className="panel padded">
            <div className="panel-heading">
              <div>
                <h2>Invoice applications</h2>
                <p>
                  Independent of operational matches. Unknown means evidence is
                  incomplete, not zero.
                </p>
              </div>
            </div>
            <div className="recon-totals">
              {[
                ["Invoice amount", review.totals.invoice_amount_minor],
                ["Applied", review.totals.invoice_applied_minor],
                ["Open", review.totals.invoice_open_minor],
                ["Recognized revenue", review.totals.recognized_revenue_minor],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{formatMoney(value)}</strong>
                </div>
              ))}
            </div>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Invoice / customer</th>
                    <th>Amount</th>
                    <th>Applied</th>
                    <th>Open</th>
                    <th>Evidence</th>
                  </tr>
                </thead>
                <tbody>
                  {review.invoices.map((i) => (
                    <tr key={i.id}>
                      <td>
                        <strong>{i.id}</strong>
                        <small>
                          {customers.find((c) => c.id === i.customer_id)
                            ?.name || i.customer_id}{" "}
                          · charge {i.charge_id}
                        </small>
                      </td>
                      <td>{formatMoney(i.amount_minor)}</td>
                      <td>{formatMoney(i.applied_minor)}</td>
                      <td>{formatMoney(i.open_minor)}</td>
                      <td>
                        {i.application_status}
                        {i.applications.map((a) => (
                          <div className="recon-evidence" key={a.id}>
                            {a.id} · {a.receipt_id} ·{" "}
                            {formatMoney(a.minor_units)} · {a.status} ·{" "}
                            {a.recorded_at}
                            {a.reason && ` · ${a.reason}`}
                            {a.reversal_of_id &&
                              ` · reverses ${a.reversal_of_id}`}
                            {role === "finance" &&
                              review.mode === "current" &&
                              !a.reversal_of_id &&
                              a.status !== "reversed" && (
                                <button
                                  className="text-button"
                                  disabled={!canWrite}
                                  onClick={() =>
                                    command("REVERSE_INVOICE_APPLICATION", {
                                      application_id: a.id,
                                      ...common,
                                    })
                                  }
                                >
                                  Reverse
                                </button>
                              )}
                          </div>
                        ))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {!review.invoices.length && (
              <p className="help">No invoices in this period.</p>
            )}
          </section>
          <section className="panel padded">
            <div className="panel-heading">
              <div>
                <h2>Bank batch proof</h2>
                <p>
                  Gross = fees + net. Entity-level amounts are not customer
                  deposits or advisor earnings.
                </p>
              </div>
            </div>
            <div className="recon-totals">
              {[
                ["Gross", review.totals.bank_gross_minor],
                ["Fees", review.totals.bank_fee_minor],
                ["Net", review.totals.bank_net_minor],
              ].map(([label, value]) => (
                <div key={label}>
                  <span>{label}</span>
                  <strong>{formatMoney(value)}</strong>
                </div>
              ))}
            </div>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Batch / receipts</th>
                    <th>Gross</th>
                    <th>Fee</th>
                    <th>Net</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {review.bank_batches.map((b) => (
                    <tr key={b.id}>
                      <td>
                        <strong>{b.id}</strong>
                        <small>{b.receipt_ids.join(", ")}</small>
                      </td>
                      <td>{formatMoney(b.gross_minor)}</td>
                      <td>{formatMoney(b.fee_minor)}</td>
                      <td>{formatMoney(b.net_minor)}</td>
                      <td>
                        {b.status} · {b.recorded_at}
                        {b.reversal && (
                          <small>
                            Reversal {b.reversal.id} · {b.reversal.recorded_at}{" "}
                            · {b.reversal.reason}
                          </small>
                        )}
                        {role === "finance" &&
                          review.mode === "current" &&
                          b.status !== "reversed" && (
                            <button
                              className="text-button"
                              disabled={!canWrite}
                              onClick={() =>
                                command("REVERSE_BANK_BATCH", {
                                  batch_id: b.id,
                                  ...common,
                                })
                              }
                            >
                              Reverse
                            </button>
                          )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {!review.bank_batches.length && (
              <p className="help">
                No bank batch evidence supplied for this period.
              </p>
            )}
          </section>
          <section className="panel padded">
            <div className="panel-heading">
              <div>
                <h2>Exceptions and next actions</h2>
                <p>Conflicts remain visible until separately corrected.</p>
              </div>
            </div>
            {review.exceptions.length ? (
              exceptions(review.exceptions)
            ) : (
              <p className="help">No exceptions reported for this review.</p>
            )}
            {review.mode === "frozen" && (
              <>
                <h3>Changes after this review</h3>
                {exceptions(review.late_exceptions || [])}
                {review.later_evidence.length ? (
                  review.later_evidence.map((e) => (
                    <p key={e.id}>
                      <strong>{e.kind}</strong> · {e.id} · {e.recorded_at}
                      <br />
                      {e.reason}
                    </p>
                  ))
                ) : (
                  <p className="help">No later evidence reported.</p>
                )}
              </>
            )}
          </section>
          {role === "finance" && review.mode === "current" && (
            <section className="panel padded">
              <div className="panel-heading">
                <div>
                  <h2>Record finance evidence</h2>
                  <p>
                    Enter dollar amounts with up to two decimal places. A reason
                    and business date apply to each action, including reversals.
                  </p>
                </div>
              </div>
              <div className="recon-form">
                <label className="field">
                  Business date
                  <input
                    type="date"
                    value={date}
                    onChange={(e) => setDate(e.target.value)}
                  />
                </label>
                <label className="field">
                  Reason
                  <input
                    value={reason}
                    maxLength={300}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Describe the evidence or decision"
                  />
                </label>
              </div>
              <div className="recon-form">
                <h3>Invoice application</h3>
                <label className="field">
                  Invoice
                  <select
                    value={invoice}
                    onChange={(e) => {
                      setInvoice(e.target.value);
                      setReceipt("");
                    }}
                  >
                    <option value="">Choose an invoice</option>
                    {review.invoices.map((i) => (
                      <option key={i.id} value={i.id}>
                        {customers.find((c) => c.id === i.customer_id)?.name ||
                          i.customer_id}{" "}
                        · {formatMoney(i.amount_minor)} · {i.id}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Verified receipt
                  <select
                    value={receipt}
                    onChange={(e) => setReceipt(e.target.value)}
                  >
                    <option value="">Choose a receipt</option>
                    {receiptOptions
                      .filter(
                        (r) =>
                          !invoice ||
                          r.customer ===
                            review.invoices.find((i) => i.id === invoice)
                              ?.customer_id,
                      )
                      .map((r) => (
                        <option key={r.id} value={r.id}>
                          {r.customer_name} · {formatMoney(r.amount_minor)} ·{" "}
                          {r.id}
                        </option>
                      ))}
                  </select>
                </label>
                <label className="field">
                  Application amount (USD)
                  <input
                    inputMode="decimal"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.00"
                  />
                </label>
                <button
                  className="secondary"
                  disabled={
                    !canWrite ||
                    !invoice ||
                    !receipt ||
                    applicationCents === null ||
                    applicationCents === "0"
                  }
                  onClick={() =>
                    command("RECORD_INVOICE_APPLICATION", {
                      invoice_id: invoice,
                      receipt_id: receipt,
                      minor_units: applicationCents,
                      ...common,
                    })
                  }
                >
                  Record application
                </button>
              </div>
              <div className="recon-form">
                <h3>Bank batch</h3>
                <p>
                  Select the verified receipts included in this entity-level
                  batch.
                </p>
                <fieldset className="recon-receipts">
                  <legend>Receipts</legend>
                  {receiptOptions.length ? (
                    receiptOptions.map((r) => (
                      <label key={r.id}>
                        <input
                          type="checkbox"
                          checked={selectedReceipts.includes(r.id)}
                          onChange={(e) =>
                            setSelectedReceipts(
                              e.target.checked
                                ? [...selectedReceipts, r.id]
                                : selectedReceipts.filter((id) => id !== r.id),
                            )
                          }
                        />
                        <span>
                          {r.customer_name} · {formatMoney(r.amount_minor)}{" "}
                          <small>{r.id}</small>
                        </span>
                      </label>
                    ))
                  ) : (
                    <p>No verified receipts are available.</p>
                  )}
                </fieldset>
                <div className="recon-derived">
                  <span>
                    Gross <strong>{formatMoney(grossCents.toString())}</strong>
                  </span>
                  <span>
                    Net{" "}
                    <strong>
                      {netCents === null
                        ? "Enter a valid fee"
                        : formatMoney(netCents)}
                    </strong>
                  </span>
                </div>
                <label className="field">
                  Bank fee (USD)
                  <input
                    inputMode="decimal"
                    value={fee}
                    onChange={(e) => setFee(e.target.value)}
                    placeholder="0.00"
                  />
                </label>
                <button
                  className="secondary"
                  disabled={
                    !canWrite ||
                    !selectedReceipts.length ||
                    feeCents === null ||
                    netCents === null
                  }
                  onClick={async () => {
                    const result = await command("RECORD_BANK_BATCH", {
                      id: `batch-${crypto.randomUUID()}`,
                      receipt_ids: selectedReceipts,
                      gross_minor: grossCents.toString(),
                      fee_minor: feeCents,
                      net_minor: netCents,
                      ...common,
                    });
                    if (result) {
                      setSelectedReceipts([]);
                      setFee("");
                    }
                  }}
                >
                  Record batch
                </button>
              </div>
              <div className="recon-form">
                <h3>Save this review</h3>
                <p>
                  Freeze current evidence for comparison. The manifest is
                  checked against intervening changes.
                </p>
                <button
                  className="primary"
                  disabled={!canWrite}
                  onClick={async () => {
                    const result = (await command("CLOSE_RECONCILIATION", {
                      period_start: period.start,
                      period_end_exclusive: period.end,
                      expected_manifest_hash: review.manifest_hash,
                      reason: reason.trim(),
                    })) as { id?: string } | null;
                    if (result?.id) setCloseId(result.id);
                  }}
                >
                  Save review
                </button>
              </div>
            </section>
          )}
          {role !== "finance" && review.mode === "current" && (
            <p className="help">
              The simulated Finance role can record evidence and save reviews.
            </p>
          )}
        </>
      )}
    </div>
  );
}
