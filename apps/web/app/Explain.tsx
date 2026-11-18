"use client";
import { useEffect, useId, useRef, useState } from "react";

export type RecordData = Record<string, any>;
export function dollars(value: unknown) {
  if (value == null || !/^-?\d+$/.test(String(value))) return "Not available";
  const n = BigInt(String(value)), a = n < 0n ? -n : n;
  return `${n < 0n ? "−" : ""}$${(a / 100n).toLocaleString("en-US")}.${String(a % 100n).padStart(2, "0")}`;
}
export function displayDate(value?: string | null, exclusive = false) {
  if (!value) return "Ongoing";
  const date = new Date(`${value.slice(0, 10)}T00:00:00Z`);
  if (exclusive) date.setUTCDate(date.getUTCDate() - 1);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleDateString("en-US", { timeZone: "UTC", month: "short", day: "numeric", year: "numeric" });
}
export function Modal({ title, subtitle, children, onClose, wide = false }: {
  title: string; subtitle?: string; children: React.ReactNode; onClose: () => void; wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null), titleId = useId();
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    ref.current?.showModal();
    return () => { ref.current?.close(); document.body.style.overflow = overflow; previous?.focus(); };
  }, []);
  return <dialog ref={ref} aria-labelledby={titleId} className={`ex-modal ${wide ? "ex-modal--wide" : ""}`}
    onCancel={event => { event.preventDefault(); onClose(); }}
    onClick={event => { if (event.target === event.currentTarget) {
      const box = event.currentTarget.getBoundingClientRect();
      if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) onClose();
    } }}>
    <header><div><h2 id={titleId}>{title}</h2>{subtitle && <p>{subtitle}</p>}</div><button className="ex-close" onClick={onClose} aria-label="Close dialog">×</button></header>
    <div className="ex-modal-body">{children}</div>
  </dialog>;
}

export function DocumentMark({ kind = "document" }: { kind?: "document" | "money" | "terms" | "check" | "calendar" }) {
  return <svg className="ex-mark" viewBox="0 0 48 48" fill="none" aria-hidden="true">
    {kind === "money" ? <><rect x="5" y="12" width="38" height="25" rx="4"/><path d="M10 18h4M34 31h4"/><circle cx="24" cy="24" r="7"/><path d="M24 20v8m2-6c0-2-4-2-4 0s4 2 4 4-4 2-4 0"/></> :
      kind === "check" ? <><circle cx="24" cy="24" r="17"/><path d="m15 24 6 6 12-13"/></> :
      kind === "terms" ? <><path d="M10 9h22l7 7v24H10zM32 9v9h7M16 25h16M16 32h11"/><circle cx="19" cy="17" r="3"/></> :
      kind === "calendar" ? <><rect x="7" y="11" width="34" height="30" rx="3"/><path d="M7 21h34M16 6v10M32 6v10M15 29h5M28 29h5M15 35h5"/></> :
      <><path d="M12 6h17l9 9v27H12zM29 6v10h9M18 24h14M18 31h14M18 37h8"/></>}
  </svg>;
}

export function Flow({ steps }: { steps: { title: string; label: string; value?: string; kind?: "document" | "money" | "terms" | "check" | "calendar"; onClick: () => void }[] }) {
  return <div className="ex-flow" role="group" aria-label="Explore the workflow">{steps.map((step, i) => <div className="ex-flow-part" key={step.title}>
    <button className="ex-flow-step" onClick={step.onClick}><span className="ex-step-index">{String(i + 1).padStart(2, "0")}</span><DocumentMark kind={step.kind}/><strong>{step.title}</strong>{step.value && <b>{step.value}</b>}<span>{step.label}</span><small>Explore →</small></button>
    {i < steps.length - 1 && <span className="ex-flow-arrow" aria-hidden="true">→</span>}
  </div>)}</div>;
}

export function Evidence({ record }: { record: RecordData }) {
  const facts = [
    ["Source", record.mocked || record.source === "mock_accounting" ? "Campfire mock" : record.source?.replaceAll("_", " ")],
    ["Period", record.period || record.posting_period], ["Status", record.status?.replaceAll("_", " ")],
    ["Recorded amount", record.amount_minor != null ? dollars(record.amount_minor) : null],
    ["Received", record.received_at || record.observed_at ? displayDate(record.received_at || record.observed_at) : null],
    ["Reference", record.record_id || record.id || record.invoice_id],
  ].filter(([, value]) => value != null);
  return <><dl className="ex-evidence">{facts.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl><details className="ex-technical"><summary>Record references and original fields</summary><pre>{JSON.stringify(record, null, 2)}</pre></details></>;
}

type PdfDocument = { name: string; url: string; edition: string; pages?: number; previewPrefix?: string; source?: string; description?: string };

function DocumentViewer({ document, onClose }: { document: PdfDocument; onClose: () => void }) {
  const [page, setPage] = useState(1);
  const pageCount = document.pages || 1;
  return <Modal title={document.name} subtitle={document.edition} onClose={onClose} wide>
    <div className="ex-document-tools"><span>{document.source ? <a href={document.source} target="_blank" rel="noreferrer">Source: Savvy Wealth ↗</a> : document.edition}</span><div><a className="ws-secondary" href={document.url} target="_blank" rel="noreferrer">Open PDF ↗</a><a className="ws-primary" href={document.url} download>Download PDF ↓</a></div></div>
    {document.previewPrefix ? <>
      <nav className="ex-document-pages" aria-label="Document pages"><button className="ws-secondary" disabled={page === 1} onClick={() => setPage(page - 1)}>Previous page</button><label>Page <select aria-label="Document page" value={page} onChange={event => setPage(Number(event.target.value))}>{Array.from({length: pageCount}, (_, i) => <option key={i} value={i + 1}>{i + 1}</option>)}</select> of {pageCount}</label><button className="ws-secondary" disabled={page === pageCount} onClick={() => setPage(page + 1)}>Next page</button></nav>
      <div className="ex-pdf-preview"><img src={`${document.previewPrefix}-${String(page).padStart(2, "0")}.png`} alt={`${document.name}, page ${page} of ${pageCount}`} /></div>
    </> : <><p>If the document does not appear below, use Open PDF to read it in a new tab.</p><iframe className="ex-pdf-frame" title={document.name} src={document.url} /></>}
  </Modal>;
}

// Only an explicitly registered, document/version-matched agreement can open here.
// Public disclosures must never stand in for an executed agreement.
const AGREEMENT_DOCUMENTS: Record<string, PdfDocument> = {};
export function AgreementDocument({ term }: { term: { document_ref?: { document_id: string; version: string } | null } }) {
  const [open, setOpen] = useState(false);
  const ref = term.document_ref;
  const document = ref && AGREEMENT_DOCUMENTS[`${ref.document_id}:${ref.version}`];
  if (!document) return <p className="ws-footnote">Agreement PDF not yet available.</p>;
  return <><button className="ws-secondary" onClick={() => setOpen(true)}>View agreement ↗</button>{open && <DocumentViewer document={document} onClose={() => setOpen(false)} />}</>;
}

const DISCLOSURES: PdfDocument[] = [
  { name: "Form ADV Part 2A", edition: "March 31, 2026 · 31 pages", url: "/disclosures/savvy-form-adv-2026-03-31.pdf", pages: 31, previewPrefix: "/disclosures/savvy-form-adv-2026-03-31", source: "https://info.savvywealth.com/hubfs/Form%20ADV%20%2B%20CRS/Savvy-Advisors-ADV.pdf", description: "Savvy Advisors’ services, fees and business practices." },
  { name: "Form CRS", edition: "March 2026 · 2 pages", url: "/disclosures/savvy-form-crs-2026-03.pdf", pages: 2, previewPrefix: "/disclosures/savvy-form-crs-2026-03", source: "https://info.savvywealth.com/hubfs/Form%20ADV%20%2B%20CRS/Savvy-Advisors-CRS.pdf", description: "Savvy Advisors’ customer relationship summary." },
];
export function SavvyDisclosures() {
  const [document, setDocument] = useState<PdfDocument | null>(null);
  return <section className="ex-disclosures" aria-label="Savvy public disclosures"><div className="ex-section-heading"><h2>Savvy disclosures</h2></div><p>Public information about Savvy Advisors. These disclosures are separate from your business agreement.</p><div className="ex-disclosure-grid">{DISCLOSURES.map(item => <article className="ws-panel ex-disclosure-card" key={item.url}><DocumentMark /><h3>{item.name}</h3><small>{item.edition}</small><p>{item.description}</p><div className="ex-document-tools"><div><button className="ws-secondary" onClick={() => setDocument(item)}>View {item.name} ↗</button><a className="ws-secondary" href={item.url} download>Download PDF ↓</a></div></div></article>)}</div>{document && <DocumentViewer key={document.url} document={document} onClose={() => setDocument(null)} />}</section>;
}
