"use client";
import { useState } from "react";
import { SavvyDisclosures, AgreementDocument, dollars, displayDate, Evidence, Flow, Modal, type RecordData } from "./Explain";
import { Adjustments, PolicyEditor, type Data } from "./MedallionViews";

export default function ProductWorkspace({data,internal,busy,command,onQueue,onLineage,children}: {
  data:Data; internal:Data|null; busy:boolean;
  command:(action:string,input:unknown,role?:string)=>Promise<unknown>;
  onQueue:()=>void;onLineage:()=>void;children?:React.ReactNode;
}) {
  const [panel,setPanel]=useState<string|null>(null);
  const current=data.terms.find(t=>["current","applied"].includes(t.status));
  const run=data.run;
  const total=run?.summary.find(x=>x.output_id===(data.case_id==="advisor"?"compensation":"net"));
  const requests=Number((internal?.request_queue as RecordData | undefined)?.total || 0);
  const stages=[
    {title:"Activity",label:"Balances, accounts & events",kind:"document" as const},
    {title:"Agreement",label:"The terms that apply",kind:"terms" as const},
    {title:"Calculation",label:"Fees, credits & compensation",kind:"calendar" as const},
    {title:"Statement",label:"What the broker sees",kind:"check" as const},
  ];
  return <>
    <div className="ex-page-heading"><div><span className="ws-eyebrow">INTERNAL PRODUCT</span><h1>From an agreement to a statement.</h1><p>Follow the current result, or change the terms behind it.</p></div><button className="ws-primary" onClick={()=>setPanel("change")}>Change terms →</button></div>
    <section className="ex-workflow-section"><div className="ex-section-heading"><h2>How this business is billed</h2><span>Click a step to explore</span></div>
      <Flow steps={stages.map((s,i)=>({...s,value:i===2 && total?dollars(total.minor):undefined,onClick:()=>setPanel(s.title)}))}/>
    </section>
    <div className="ex-product-columns">
      <section className="ws-panel ex-current-agreement"><div className="ex-section-heading"><h2>Current agreement</h2><span className="ws-badge">{current?"Active for this period":"Not available"}</span></div><h3>{current?.title || "No applied agreement"}</h3>{current && <><p>{displayDate(current.period_start)} – {displayDate(current.period_end,true)}</p><dl className="ex-compact-terms">{current.items.filter(x=>/floor|monthly|cap|Standard advisor|Qualified receipt|price per/i.test(x.label)).map(x=><div key={x.label}><dt>{x.label}</dt><dd>{x.value}</dd></div>)}</dl><AgreementDocument term={current}/><button className="ws-link" onClick={()=>setPanel("Agreement")}>All terms and dates →</button></>}</section>
      <section className="ex-product-actions"><span className="ws-eyebrow">WHAT DO YOU WANT TO DO?</span><button onClick={()=>setPanel("change")}><strong>Change an agreement</strong><span>Choose a rate or commercial component and preview its effect.</span><b>→</b></button><button onClick={onQueue}><strong>Review a request{requests?` (${requests})`:""}</strong><span>See the change, its financial impact and the next decision.</span><b>→</b></button><button onClick={()=>setPanel("item")}><strong>Add a charge, credit or payout request</strong><span>A one-time item follows the same review and billing rules.</span><b>→</b></button></section>
    </div>
    {children}
    <div className="ex-bottom-link"><span>Need to see exactly where a number came from?</span><button className="ws-link" onClick={onLineage}>Open record lineage →</button></div>
    {panel && <Modal title={panel==="change"?"Propose a terms change":panel==="item"?"Add a one-time item":panel==="Agreement"?"The agreement behind this result":panel==="Calculation"?"One engine applies the agreement":panel==="Activity"?"Start with received activity":"The broker's statement"} onClose={()=>setPanel(null)} wide={panel==="change"||panel==="item"}>
      {panel==="change" ? internal?<><p className="ex-modal-intro">Choose a component, enter the terms and save a draft. Your current agreement stays in force while the request is reviewed.</p><PolicyEditor data={internal} busy={busy} command={command}/><div className="ex-modal-footer"><button className="ws-secondary" onClick={()=>{setPanel(null);onQueue()}}>Review impact in the work queue →</button></div></>:<p>Loading terms…</p> : panel==="item" ? internal?<Adjustments data={internal} busy={busy} command={command}/>:<p>Loading request tools…</p> : panel==="Activity" ? <><p className="ex-modal-intro">The system keeps the original balance reports, account activity and one-time events. It validates and maps those records before using them in a calculation.</p><div className="ex-mini-pipeline"><span>Original records</span><b>→</b><span>Validated activity</span><b>→</b><span>Selected terms</span></div><dl className="ex-evidence"><div><dt>Service period</dt><dd>{displayDate(run?.period_start)} – {displayDate(run?.period_end,true)}</dd></div><div><dt>Evidence known by</dt><dd>{displayDate(run?.knowledge_cutoff)}</dd></div></dl><p>Corrections create new versions. They do not erase the original report or a previous statement.</p><button className="ws-secondary" onClick={()=>{setPanel(null);onLineage()}}>Inspect an original record →</button></> : panel==="Agreement" ? <><p className="ex-modal-intro">The agreement determines rates, dates, eligibility, promotions and caps or guarantees. Changing a deal means publishing a new policy through the API.</p>{current?<><dl className="ex-compact-terms">{current.items.map(x=><div key={x.label}><dt>{x.label}</dt><dd>{x.value}</dd></div>)}</dl><AgreementDocument term={current}/></>:<p>No governing terms are available.</p>}<SavvyDisclosures /><p>Draft → compare impact → Legal and Finance review → publish → assign. Saving a draft does not activate it.</p></> : panel==="Calculation" ? <><p className="ex-modal-intro">The same billing engine processes both products. It applies the selected policy to the recorded activity and retains the calculation behind every amount.</p><div className="ex-amount-list">{run?.summary.map(x=><div key={x.output_id}><span>{x.label}</span><strong>{dollars(x.minor)}</strong></div>)}</div><p>Recurring fees, targeted promotions, guarantees and one-time items use that same engine. The interface and reporting jobs do not calculate a second set of prices.</p><button className="ws-secondary" onClick={()=>{setPanel(null);onLineage()}}>Follow the calculation records →</button></> : <><p className="ex-modal-intro">A statement presents the selected billing result as dated line items. Each line retains its agreement, service period and calculation basis.</p><p>Charges and earnings are separate from payment evidence. A payout request does not prove payment, and a credit does not prove a refund.</p>{run && <Evidence record={{id:run.id,status:run.status,period:`${displayDate(run.period_start)} – ${displayDate(run.period_end,true)}`}}/>}</>}
    </Modal>}
  </>;
}
