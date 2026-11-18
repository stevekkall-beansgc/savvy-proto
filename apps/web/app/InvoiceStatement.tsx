"use client";
import { useEffect, useRef, useState } from "react";
import { Agreements } from "./MedallionViews";
import { dollars, displayDate, Modal, type RecordData as Row } from "./Explain";

type Request=(query:string,variables:Row)=>Promise<Row>;
const QUERY=`query($caseId:ID!,$limit:Int,$offset:Int){audienceStatement(caseId:$caseId,limit:$limit,offset:$offset)}`;
export default function InvoiceStatement({caseId,request,internal=false,renderClient,renderRecord}:{
  caseId:string;request:Request;internal?:boolean;
  renderClient:(data:Row)=>React.ReactNode;renderRecord:(data:Row)=>React.ReactNode;
}) {
  const [data,setData]=useState<Row|null>(null),[offset,setOffset]=useState(0),[error,setError]=useState("");
  const [line,setLine]=useState<Row|null>(null),[linked,setLinked]=useState<{kind:string;data:Row}|null>(null);
  const generation=useRef(0),limit=10;
  useEffect(()=>{let live=true;generation.current++;setData(null);setLine(null);setLinked(null);setError("");request(QUERY,{caseId,limit,offset}).then(r=>{if(live)setData(r.audienceStatement)}).catch(e=>{if(live)setError(e.message)});return()=>{live=false;generation.current++}},[caseId,request,offset]);
  async function openLink(kind:"client"|"record",id:string) {
    const current=++generation.current;setError("");
    const query=kind==="client"?`query($caseId:ID!,$id:ID!){audienceClient(caseId:$caseId,clientId:$id)}`:`query($caseId:ID!,$id:ID!){lineageRecord(caseId:$caseId,recordId:$id)}`;
    try{const r=await request(query,{caseId,id});if(current===generation.current){setLinked({kind,data:r[kind==="client"?"audienceClient":"lineageRecord"]});setLine(null)}}catch(e){if(current===generation.current)setError((e as Error).message)}
  }
  return <section className="ws-panel ex-statement">
    <div className="ex-statement-heading"><div><span className="ws-eyebrow">STATEMENT</span><h2>{caseId==="advisor"?"Advisor compensation":"Platform services"}</h2><p>{data?.service_start?`${displayDate(data.service_start)} – ${displayDate(data.service_end_exclusive,true)}`:"Loading service period…"}</p></div>{data&&<dl><div><dt>Business</dt><dd>{caseId==="advisor"?"Advisor business":"Harbor RIA"}</dd></div><div><dt>Statement as of</dt><dd>{displayDate(data.as_of)}</dd></div><div><dt>Currency</dt><dd>{data.currency||"USD"}</dd></div></dl>}</div>
    {error&&<div role="alert" className="ws-alert">{error}</div>}
    {!data?<p>{error?"Unable to load the statement.":"Loading statement lines…"}</p>:linked?<><button className="aud-back" onClick={()=>{generation.current++;setLinked(null)}}>← Back to statement</button>{linked.kind==="client"?renderClient(linked.data):renderRecord(linked.data)}</>:<>
      <div className="ex-table-scroll"><table className="ex-table ex-invoice-lines"><thead><tr><th>#</th><th>Description</th><th>Service period</th><th className="ex-number">Qty</th><th className="ex-number">Unit price</th><th className="ex-number">Amount</th></tr></thead><tbody>{(data.lines||[]).map((item:Row,i:number)=>{const l=item.invoice_line||{};return <tr key={l.id||i}><td>{l.line_number||offset+i+1}</td><td><button className="ex-line-link" onClick={()=>setLine(item)}>{l.description||item.label}<span>View calculation →</span></button></td><td className="ex-service-dates">{displayDate(l.service_period_start||data.service_start)}<span>through {displayDate(l.service_period_end_exclusive||data.service_end_exclusive,true)}</span></td><td className="ex-number">{l.quantity??"—"}</td><td className="ex-number">{l.unit_amount_minor!=null?dollars(l.unit_amount_minor):"Per agreement"}</td><td className="ex-number"><strong>{dollars(l.amount_minor??item.minor)}</strong></td></tr>})}</tbody></table></div>
      {!data.lines?.length&&<p className="ws-empty">No statement lines are available for this period.</p>}
      <div className="aud-pagination"><span>{data.total?`${offset+1}–${Math.min(offset+limit,data.total)} of ${data.total} lines`:"0 lines"}</span><div><button disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-limit))}>Previous</button><button disabled={offset+limit>=data.total} onClick={()=>setOffset(offset+limit)}>Next</button></div></div>
      <div className="ex-statement-total"><span>{caseId==="advisor"?"Remaining payable":"Statement balance"}</span><strong>{dollars(data.balance_minor)}</strong></div>
      {!!data.pending_items?.length&&<div className="ex-pending-items"><h3>Pending activity</h3>{data.pending_items.map((p:Row,i:number)=><div key={i}><span>{p.label} · {String(p.status).replaceAll("_"," ")}</span><strong>{dollars(p.minor)}</strong></div>)}</div>}
    </>}
    {line&&<Modal title={line.invoice_line?.description||line.label} subtitle={`Service period · ${displayDate(line.invoice_line?.service_period_start||data?.service_start)} – ${displayDate(line.invoice_line?.service_period_end_exclusive||data?.service_end_exclusive,true)}`} onClose={()=>setLine(null)}>
      <div className="ex-line-amount"><span>Statement line amount</span><strong>{dollars(line.minor)}</strong></div>
      <h3>How this amount was determined</h3><p>{line.basis?.description||"The selected agreement was applied to the recorded activity for this service period."}</p>
      {!!line.basis?.components?.length&&<dl className="ex-amount-list">{line.basis.components.map((c:Row,i:number)=><div key={i}><dt>{c.label}</dt><dd>{dollars(c.minor)}</dd></div>)}</dl>}
      {line.reason&&<p>{line.reason}</p>}
      {!!line.governing_terms?.length&&<div className="ex-line-terms"><h3>Governing agreement</h3><Agreements terms={line.governing_terms}/></div>}
      <div className="ex-modal-footer">{(line.client_ids||[]).map((id:string)=><button className="ws-secondary" key={id} onClick={()=>openLink("client",id)}>Open {id.replaceAll("-"," ")} account →</button>)}{internal&&line.source_record_id&&<button className="ws-secondary" onClick={()=>openLink("record",String(line.source_record_id))}>Follow source records →</button>}</div>
    </Modal>}
  </section>;
}
