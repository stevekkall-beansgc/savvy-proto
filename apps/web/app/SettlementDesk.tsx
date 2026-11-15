"use client";
import { useState } from "react";
type Minor = string | number | null | undefined;
type Grant = {
  id: string;
  payer: string;
  payee: string;
  component: string;
  opening_minor: Minor;
  applied_minor: Minor;
  remaining_minor: Minor;
  upfront_cash_minor: Minor;
};
type Obligation = {
  id: string;
  broker_id: string;
  label: string;
  payer: string;
  payee: string;
  amount_minor: Minor;
  applied_minor: Minor;
  uncovered_minor: Minor;
  suggested_grant_id: string | null;
  suggested_minor: Minor;
};
type Entry = {
  id: string;
  grant_id: string;
  obligation_id: string;
  kind: string;
  minor_units: Minor;
  reason: string;
  recorded_at: string;
  original_entry_id: string | null;
  reversed: boolean;
};
export type SettlementLedger = {
  synthetic: boolean;
  grants: Grant[];
  obligations: Obligation[];
  entries: Entry[];
  note: string;
};
type Props = {
  ledger: SettlementLedger | null;
  broker: string;
  role: string;
  busy: boolean;
  formatMoney: (m: Minor) => string;
  command: (
    action: string,
    input: unknown,
    asRole?: string,
  ) => Promise<unknown>;
};
export default function SettlementDesk({
  ledger,
  broker,
  role,
  busy,
  formatMoney,
  command,
}: Props) {
  const [reason, setReason] = useState("");
  if (!ledger)
    return <div className="empty">The settlement book is not available.</div>;
  const grants = ledger.grants.filter((g) =>
    [g.payer, g.payee].includes(broker),
  );
  const obligations = ledger.obligations.filter((o) => o.broker_id === broker);
  const entries = ledger.entries.filter((e) =>
    grants.some((g) => g.id === e.grant_id),
  );
  const canRecord = role === "finance" && !busy && reason.trim().length >= 3;
  const party = (id: string) =>
    id === "firm-demo"
      ? "Firm"
      : id === "broker-alex"
        ? "Alex"
        : id === "broker-jordan"
          ? "Jordan"
          : id;
  return (
    <>
      <div className="note wide">
        <strong>Recorded coverage is separate from a projection</strong>
        <p>
          These approved fictional obligations are worked settlement examples,
          independent of the current book’s earnings. An application uses
          coverage; it does not send money or post an accounting entry. Opposite
          directions are kept separate.
        </p>
      </div>
      <div className="grant-grid">
        {grants.map((g) => (
          <section className="panel padded grant-card" key={g.id}>
            <div className="grant-direction">
              {party(g.payer)} <span aria-hidden="true">→</span>{" "}
              {party(g.payee)}
            </div>
            <h2>
              {g.payer === "firm-demo"
                ? "Advisor advance"
                : "Broker prepurchase"}
            </h2>
            <p>
              {g.id} · {g.component.replaceAll("_", " ")}
            </p>
            <dl className="grant-balances">
              <div>
                <dt>Opening coverage</dt>
                <dd>{formatMoney(g.opening_minor)}</dd>
              </div>
              <div>
                <dt>Recorded net application</dt>
                <dd>{formatMoney(g.applied_minor)}</dd>
              </div>
              <div>
                <dt>Remaining coverage</dt>
                <dd>{formatMoney(g.remaining_minor)}</dd>
              </div>
            </dl>
            <p className="help">
              Original illustrative upfront amount:{" "}
              {formatMoney(g.upfront_cash_minor)}. Coverage is not a new cash
              receipt or payment.
            </p>
          </section>
        ))}
      </div>
      <section className="panel padded">
        <div className="panel-heading">
          <div>
            <h2>Approved fictional obligations</h2>
            <p>
              Billing and entitlement remain visible even when coverage makes
              incremental cash zero.
            </p>
          </div>
          <span className="pill gray">USD · No automatic netting</span>
        </div>
        <label className="field">
          Reason for the recorded application or reversal
          <input
            aria-label="Settlement reason"
            value={reason}
            maxLength={300}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Describe the fictional finance decision"
            disabled={role !== "finance"}
          />
        </label>
        {role !== "finance" && (
          <p className="help">
            Use the simulated Finance role to record applications or reversals.
          </p>
        )}
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Obligation / direction</th>
                <th>Full amount</th>
                <th>Applied</th>
                <th>Uncovered</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {obligations.map((o) => (
                <tr key={o.id}>
                  <td>
                    <strong>{o.label}</strong>
                    <small>
                      {party(o.payer)} → {party(o.payee)}
                    </small>
                  </td>
                  <td>{formatMoney(o.amount_minor)}</td>
                  <td>{formatMoney(o.applied_minor)}</td>
                  <td>{formatMoney(o.uncovered_minor)}</td>
                  <td>
                    <button
                      className="secondary"
                      disabled={
                        !canRecord ||
                        !o.suggested_grant_id ||
                        String(o.suggested_minor) === "0"
                      }
                      onClick={() =>
                        command("CONSUME_ENTITLEMENT", {
                          grant_id: o.suggested_grant_id,
                          obligation_id: o.id,
                          minor_units: o.suggested_minor,
                          reason,
                        })
                      }
                    >
                      Apply {formatMoney(o.suggested_minor)} coverage
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>Application and reversal history</h2>
            <p>
              Every reversal points to the original entry and restores that
              grant exactly once.
            </p>
          </div>
        </div>
        {entries.length === 0 ? (
          <div className="empty">
            No recorded applications yet. Projections do not create entries
            here.
          </div>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Event</th>
                  <th>Coverage</th>
                  <th>Reason</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {entries.map((e) => (
                  <tr key={e.id}>
                    <td>
                      <strong>
                        {e.kind === "consume"
                          ? "Coverage applied"
                          : "Coverage restored"}
                      </strong>
                      <small>
                        Entry {e.id}
                        {e.original_entry_id
                          ? ` · reverses ${e.original_entry_id}`
                          : ""}{" "}
                        · {e.grant_id}
                      </small>
                      <small>{e.recorded_at}</small>
                    </td>
                    <td>{formatMoney(e.minor_units)}</td>
                    <td className="reason-cell">{e.reason}</td>
                    <td>
                      {e.kind === "consume" ? (
                        <button
                          className="secondary"
                          disabled={!canRecord || e.reversed}
                          onClick={() =>
                            command("REVERSE_ENTITLEMENT", {
                              entry_id: e.id,
                              reason,
                            })
                          }
                        >
                          {e.reversed ? "Reversed" : "Reverse entry"}
                        </button>
                      ) : (
                        <span className="pill gray">
                          Original grant restored
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}
