/* Presentation only. All monetary calculations come from the Python engine. */
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const usd = new Intl.NumberFormat("en-US", {style:"currency",currency:"USD",minimumFractionDigits:2});
  const money = (cents) => usd.format(cents / 100);
  const compact = (cents) => "$" + (cents / 100000000).toFixed(2) + "m";
  const signed = (cents) => (cents < 0 ? "−" : "+") + money(Math.abs(cents));
  const date = (iso) => new Date(iso + "T12:00:00Z").toLocaleDateString("en-GB", {day:"numeric",month:"short",year:"numeric",timeZone:"UTC"});
  const shortDate = (iso) => new Date(iso + "T12:00:00Z").toLocaleDateString("en-GB", {day:"numeric",month:"short",timeZone:"UTC"});
  const offline = window.__ADVISOR_PREVIEW__ || null;
  const state = {data:null,result:null,advisor:null,preset:"baseline",sequence:0,controller:null,timer:null};

  function setBusy(busy) {
    document.body.classList.toggle("updating", busy);
    $("export-button").disabled = busy || !state.result;
    $("view-forecast").setAttribute("aria-busy", String(busy));
  }
  function showError(message) {
    $("error").textContent = message;
    $("error").hidden = false;
  }
  function renderAdvisors() {
    const captions = {"advisor-alex":"Simple revenue share","advisor-jordan":"Expenses + loan","advisor-taylor":"Changing terms + clients"};
    $("advisor-list").innerHTML = state.data.advisors.map(a => `<button class="advisor-button ${a.id === state.advisor ? "active" : ""}" data-advisor="${esc(a.id)}" aria-pressed="${a.id === state.advisor}"><span class="avatar">${esc(a.avatar_initials)}</span><span class="advisor-copy"><strong>${esc(a.name)}</strong><small>${esc(captions[a.id])}</small></span><span class="active-indicator" aria-hidden="true"></span></button>`).join("");
  }
  function renderPresets() {
    $("preset-list").innerHTML = Object.entries(state.data.presets).map(([key,p]) => `<button class="preset-button ${state.preset === key ? "active" : ""}" data-preset="${esc(key)}" title="${esc(p.description)}" aria-pressed="${state.preset === key}">${esc(p.label)}</button>`).join("");
  }
  function renderChart(f) {
    const rows = f.daily, width = 650, height = 210, left = 55, right = 12, top = 25, bottom = 27;
    const values = rows.map(r => r.aum_cents);
    const min = Math.min(...values), max = Math.max(...values);
    const padding = Math.max((max - min) * .20, max * .012);
    const low = Math.max(0, min - padding), high = max + padding;
    const x = i => left + i / (rows.length - 1) * (width - left - right);
    const y = v => top + (high - v) / (high - low) * (height - top - bottom);
    const coords = (start,end) => rows.slice(start,end).map((r,j) => `${x(start+j).toFixed(2)},${y(r.aum_cents).toFixed(2)}`).join(" ");
    const cut = rows.findLastIndex(r => r.phase === "actual");
    const base = height - bottom;
    let svg = `<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">`;
    for (let i=0;i<4;i++) {
      const value = low + (high-low)*i/3, pos = y(value);
      svg += `<line class="gridline" x1="${left}" x2="${width-right}" y1="${pos}" y2="${pos}"/><text x="${left-9}" y="${pos+3}" text-anchor="end">${esc(compact(value))}</text>`;
    }
    svg += `<polygon class="history-fill" points="${x(0)},${base} ${coords(0,cut+1)} ${x(cut)},${base}"/><polygon class="future-fill" points="${x(cut)},${base} ${coords(cut,rows.length)} ${x(rows.length-1)},${base}"/>`;
    svg += `<line class="cutoff-line" x1="${x(cut)}" x2="${x(cut)}" y1="${top}" y2="${base}"/><polyline class="history-line" points="${coords(0,cut+1)}"/><polyline class="future-line" points="${coords(cut,rows.length)}"/><circle class="point" cx="${x(cut)}" cy="${y(rows[cut].aum_cents)}" r="4"/>`;
    svg += `<rect class="cutoff-bubble" x="${x(cut)-31}" y="2" width="62" height="17" rx="4"/><text x="${x(cut)}" y="14" text-anchor="middle">${esc(shortDate(f.meta.as_of_date))} · as of</text>`;
    for (const i of [0,6,12,19,rows.length-1]) svg += `<text x="${x(i)}" y="${height-6}" text-anchor="${i===0 ? "start" : i===rows.length-1 ? "end" : "middle"}">${esc(shortDate(rows[i].date))}</text>`;
    svg += "</svg>";
    $("aum-chart").innerHTML = svg;
    $("aum-chart").setAttribute("aria-label", `Billable assets: ${money(rows[0].aum_cents)} on ${date(rows[0].date)}, ${money(rows[cut].aum_cents)} observed on ${date(f.meta.as_of_date)}, and ${money(rows.at(-1).aum_cents)} projected on ${date(f.meta.period_end)}. Vertical axis is scaled to the data. Daily values follow.`);
    $("chart-end-value").textContent = compact(rows.at(-1).aum_cents) + " at month-end";
    $("daily-rows").innerHTML = rows.map(r => `<tr><td>${esc(shortDate(r.date))}</td><td>${r.phase === "actual" ? "Observed" : "Projected"}</td><td class="numeric">${money(r.aum_cents)}</td><td class="numeric">${money(r.fee_cents)}</td></tr>`).join("");
  }
  function renderTerms(f) {
    $("contract-terms").innerHTML = f.contracts.map(c => `<div class="term-row"><div><strong>${esc(c.label)}</strong><small>${esc(shortDate(c.effective_from))} – ${esc(shortDate(c.effective_to))}</small></div><span>${c.advisor_share_bps/100}% yours</span></div>`).join("");
    $("expense-terms").innerHTML = f.expenses.length ? f.expenses.map(e => `<div class="term-row"><div>${esc(e.label)}<small>${e.treatment === "pre_share" ? "Before" : "After"} the revenue split</small></div><strong>${money(e.amount_cents)}</strong></div>`).join("") : '<div class="term-row"><span>Expense deductions</span><strong>None</strong></div>';
    $("loan-summary").hidden = f.loan.opening_balance_cents === 0;
    $("loan-summary").innerHTML = `Loan repayment capped at ${f.loan.repayment_cap_bps/100}% of available proceeds, a ${money(f.loan.scheduled_repayment_cents)} scheduled maximum, and the balance.<strong>${money(f.summary.loan_repayment_cents)} estimated repayment</strong><span>${money(f.summary.loan_remaining_cents)} principal remaining after this scenario.</span>`;
    $("client-terms").innerHTML = f.clients.map(c => `<div class="term-row"><div><strong>${esc(c.name)}</strong><small>${esc(c.status)}${c.event_date ? " · " + esc(shortDate(c.event_date)) : ""}</small><small>${compact(c.aum_cents)} · latest observed assets</small></div><span>${(c.annual_fee_bps/100).toFixed(2)}% / year</span></div>`).join("");
  }
  function renderAccounting(result) {
    const erp = result.erp, s = erp.summary, f = result.forecast;
    const gap = result.reconciliation.gap_to_full_period_forecast_cents;
    const metric = (label,value,note) => `<section class="metric"><span>${label}</span><strong>${money(value)}</strong><small>${note}</small></section>`;
    const paymentRows = erp.payments.map(p => `<tr><td>${esc(p.id)}</td><td>${esc(p.invoice_id)}</td><td>${esc(shortDate(p.payment_date))}</td><td>${esc(p.classification.replaceAll("_"," "))}</td><td><span class="status-chip ${p.included_in_observed_totals ? "" : "excluded"}">${esc(p.exclusion || p.state)}</span></td><td class="numeric">${money(p.amount_cents)}</td></tr>`).join("");
    const invoiceRows = erp.invoices.map(i => `<tr><td>${esc(i.invoice_number)}</td><td>${esc(shortDate(i.invoice_date))}</td><td class="numeric">${money(i.total_cents)}</td><td class="numeric">${money(i.amount_paid_cents)}</td><td class="numeric">${money(i.amount_due_cents)}</td></tr>`).join("");
    $("accounting-content").innerHTML = `<div class="accounting-grid">${metric("Invoiced in sample cohort",s.invoiced_cents,"Mapped to this advisor and service period")}${metric("Observed sample cash",s.cash_collected_cents,"Active cash payments only; credit memos excluded")}${metric("Credits applied",s.credits_applied_cents,"Non-cash reductions to receivables")}</div>
      <section class="panel"><div class="panel-heading"><div><h2>What still needs to be collected?</h2><p>Illustrative comparison for ${esc(f.advisor.name)} · ${esc(shortDate(f.meta.period_start))}–${esc(shortDate(f.meta.period_end))}</p></div><span class="small-badge">Not a closed-period reconciliation</span></div>
      <div class="cash-gap"><span>Expected collections by ${esc(shortDate(f.meta.next_payout_date))}</span><strong>${money(f.summary.expected_collections_cents)}</strong></div><div class="cash-gap"><span>Cash observed in the sample through ${esc(shortDate(f.meta.as_of_date))}</span><strong>${money(s.cash_collected_cents)}</strong></div><div class="cash-gap"><span>${gap === null ? "Comparison withheld until payments are classified" : gap >= 0 ? "Additional collections implied by this scenario" : "Observed cash exceeds this scenario"}</span><strong>${gap === null ? "Incomplete" : money(Math.abs(gap))}</strong></div>
      <p class="accounting-copy">This difference is between a period forecast and a fictional, explicitly mapped invoice cohort. It is not an overdue balance. Posted invoices, fee credits, timing, and final advisor eligibility still require finance review. Accounting evidence does not automatically replace the collection assumption.</p>
      ${!s.cash_classification_complete ? `<p class="notice danger">${money(s.unclassified_payments_cents)} of active payments have an unknown classification. They are excluded from cash; this comparison is incomplete.</p>` : ""}
      ${s.allocation_review_required ? `<p class="notice danger">${s.inactive_invoice_payment_count} payment allocation(s) point to an inactive invoice. Observed cash is retained, but the comparison is withheld until finance reviews the allocation.</p>` : ""}
      </section><section class="panel accounting-section"><div class="panel-heading"><div><h2>Invoice evidence</h2><p>Amounts paid can include both cash and credit memos.</p></div></div><div class="table-scroll"><table><thead><tr><th>Invoice</th><th>Issued</th><th class="numeric">Total</th><th class="numeric">Applied</th><th class="numeric">Remaining</th></tr></thead><tbody>${invoiceRows}</tbody></table></div></section>
      <section class="panel accounting-section"><div class="panel-heading"><div><h2>Payment evidence</h2><p>${s.duplicate_observations_ignored} duplicate observation(s) ignored · ${s.superseded_versions_retained} previous revision(s) retained</p></div></div><div class="table-scroll"><table><thead><tr><th>Payment</th><th>Invoice</th><th>Date</th><th>Classification</th><th>Status</th><th class="numeric">Amount</th></tr></thead><tbody>${paymentRows}</tbody></table></div><p class="accounting-copy">Voided or reversed amounts excluded: ${money(s.voided_or_reversed_cents)}. The fixture-only cash label is not a verified Campfire payment-type enum.</p></section>
      <section class="panel accounting-section accounting-copy"><h2>Mapping and source policy</h2><ul>${erp.mapping_notes.map(n=>`<li>${esc(n)}</li>`).join("")}</ul><details class="compact-details"><summary>Inspect normalized source snapshot</summary><pre class="detail-json">${esc(JSON.stringify(erp,null,2))}</pre></details></section>`;
  }
  function renderSources() {
    $("source-list").innerHTML = state.data.sources.filter(s=>s.url).map(s => {
      let url; try { url = new URL(s.url); } catch { return ""; }
      if (url.protocol !== "https:") return "";
      return `<article class="source-item"><a href="${esc(url.href)}" target="_blank" rel="noopener noreferrer">${esc(s.title)} ↗</a>${s.claims.map(claim => `<p>${esc(claim)}</p>`).join("")}<small>${esc(s.publisher)} · ${esc(s.classification)} · retrieved ${esc(s.retrieved_at)} · ${esc(s.id)}</small></article>`;
    }).join("");
  }
  function controlsFromResult(f) {
    $("market-input").value = f.scenario.market_change_bps/100;
    $("flow-input").value = f.scenario.net_flow_cents/100000000;
    $("collection-input").value = f.scenario.collection_bps/100;
    renderControlLabels();
  }
  function renderControlLabels() {
    const market = Number($("market-input").value), flow = Number($("flow-input").value);
    $("market-output").textContent = (market>0?"+":"") + market + "%";
    $("flow-output").textContent = flow === 0 ? "$0" : (flow<0?"−":"+") + "$" + Math.abs(flow).toFixed(1) + "m";
    $("collection-output").textContent = $("collection-input").value + "%";
  }
  function render(result) {
    const f = result.forecast, s = f.summary;
    state.result = result;
    $("advisor-name").textContent = f.advisor.name;
    $("advisor-description").textContent = f.advisor.description;
    $("context-avatar").textContent = f.advisor.avatar_initials;
    $("as-of").textContent = "As of " + date(f.meta.as_of_date);
    $("payout-value").textContent = money(s.estimated_payout_cents);
    $("scenario-label").textContent = state.data.presets[state.preset]?.label || "Custom scenario";
    $("payout-delta").textContent = s.delta_payout_cents === 0 ? "Matches the current outlook" : signed(s.delta_payout_cents) + " vs. current outlook";
    $("payment-date").textContent = date(f.meta.next_payout_date);
    $("earned-fees").textContent = money(s.earned_fees_cents);
    $("period-fees").textContent = money(s.projected_fees_cents);
    $("current-aum").textContent = compact(s.current_aum_cents);
    $("expected-collections").textContent = money(s.expected_collections_cents);
    $("waterfall").innerHTML = f.waterfall.filter(r=>r.amount_cents !== 0 || r.kind !== "deduction").map(r=>`<div class="waterfall-row ${r.kind === "total" ? "total" : ""}"><span class="row-label"><span class="row-symbol" aria-hidden="true">${r.kind === "total" ? "=" : r.kind === "deduction" ? "−" : "+"}</span>${esc(r.label)}</span><strong>${money(r.amount_cents)}</strong></div>`).join("");
    $("entitlement-context").textContent = `Projected advisor entitlement before loan repayment: ${money(s.advisor_entitlement_cents)}. Unapplied expense deductions: ${money(s.unapplied_deductions_cents)}. Unapplied does not mean forgiven; treatment depends on contract terms.`;
    $("assumptions-list").innerHTML = f.assumptions.map(a=>`<li>${esc(a)}</li>`).join("");
    $("model-warnings").innerHTML = f.warnings.map(w=>`<p>${esc(w)}</p>`).join("");
    $("receipt-hash").textContent = "SHA-256 · " + result.receipt.sha256;
    renderAdvisors(); renderPresets(); renderChart(f); renderTerms(f); renderAccounting(result); controlsFromResult(f);
    if (offline) $("scenario-note").textContent = `Offline preview: scenarios were computed by the same Python engine. Selected inputs: ${f.scenario.market_change_bps/100}% market move, ${signed(f.scenario.net_flow_cents)} net flows, ${f.scenario.collection_bps/100}% collected. Market and flow changes apply on 14 Nov.`;
    $("live-status").textContent = `${f.advisor.name}: estimated payout ${money(s.estimated_payout_cents)}. ${$("scenario-label").textContent}.`;
  }
  async function update(advisor, preset, scenario) {
    clearTimeout(state.timer);
    const sequence = ++state.sequence;
    state.controller?.abort();
    state.controller = new AbortController();
    setBusy(true); $("error").hidden = true;
    try {
      let result;
      if (offline) result = offline.snapshots[advisor][preset];
      else {
        const response = await fetch("/api/forecast", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({advisor_id:advisor,scenario}),signal:state.controller.signal});
        result = await response.json();
        if (!response.ok) throw new Error(result.error || "The calculation could not be completed.");
      }
      if (sequence !== state.sequence) return;
      if (!result) throw new Error("This scenario is not included in the offline preview.");
      state.advisor = advisor; state.preset = preset;
      render(result); setBusy(false);
    } catch (error) {
      if (sequence !== state.sequence || error.name === "AbortError") return;
      showError(`Could not update: ${error.message} Displayed results are the last successful calculation. Reset or choose a scenario to retry.`);
      document.body.classList.remove("updating");
      $("view-forecast").setAttribute("aria-busy","false");
    }
  }
  function view(name) {
    const titles = {forecast:["Payout outlook","See how your book and contract shape the next payment."],accounting:["Accounting evidence","Trace the forecast back to sample invoice and payment records."],research:["Assumptions & research","Understand the model, its boundaries, and the source evidence."]};
    if (!titles[name]) return;
    for (const key of Object.keys(titles)) $("view-"+key).hidden = key !== name;
    document.querySelectorAll(".nav-item[data-view]").forEach(b=>{b.classList.toggle("selected",b.dataset.view===name);if(b.dataset.view===name)b.setAttribute("aria-current","page");else b.removeAttribute("aria-current");});
    $("page-title").textContent=titles[name][0]; $("page-subtitle").textContent=titles[name][1];
  }
  document.addEventListener("click", event => {
    const nav=event.target.closest("[data-view]"); if(nav) view(nav.dataset.view);
    if(!state.data) return;
    const advisor=event.target.closest("[data-advisor]"); if(advisor) update(advisor.dataset.advisor,"baseline",{});
    const preset=event.target.closest("[data-preset]"); if(preset) update(state.advisor,preset.dataset.preset,state.data.presets[preset.dataset.preset].scenario);
  });
  $("reset-button").addEventListener("click",()=>{if(state.data)update(state.advisor,"baseline",{});});
  for (const id of ["market-input","flow-input","collection-input"]) $(id).addEventListener("input",()=>{
    if(!state.data || offline) return;
    ++state.sequence; state.controller?.abort(); clearTimeout(state.timer); setBusy(true); renderControlLabels();
    const scenario={market_change_bps:Math.round(Number($("market-input").value)*100),net_flow_cents:Math.round(Number($("flow-input").value)*100000000),collection_bps:Math.round(Number($("collection-input").value)*100)};
    state.timer=setTimeout(()=>update(state.advisor,"custom",scenario),180);
  });
  $("export-button").addEventListener("click",()=>{
    if(!state.result || $("export-button").disabled) return;
    const blob=new Blob([JSON.stringify(state.result,null,2)+"\n"],{type:"application/json"});
    const url=URL.createObjectURL(blob), anchor=document.createElement("a");
    anchor.href=url; anchor.download=`legume-payout-${state.advisor}-${state.preset}.json`; anchor.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);
  });
  async function init() {
    try {
      if(offline) {state.data=offline.bootstrap;$("live-controls").hidden=true;$("mode-badge").textContent="Offline · sample data";}
      else {const response=await fetch("/api/bootstrap");if(!response.ok)throw new Error("Could not load the sample data.");state.data=await response.json();}
      state.advisor=state.data.initial.forecast.advisor.id;
      renderSources(); render(state.data.initial); $("loading").hidden=true; setBusy(false);
    } catch(error) {$("loading").hidden=true;showError(error.message + " Start the Python server or open the self-contained offline preview.");}
  }
  init();
})();
