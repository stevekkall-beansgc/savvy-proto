'use strict';

{
  const config = JSON.parse(get('map-config').textContent);
  const importer = createTraceImport(config);
  const maxFiles = 12, maxRecords = 2000, maxBytes = 2_000_000;
  let batch = [], relationships = [], busy = false;
  const reviewRecord = get('review-record');
  const roleSelect = get('review-kind');
  const drop = get('drop-zone');
  const files = get('record-files');
  const namedTypes = new Map(Object.entries(importer.eventKinds).map(([key, name]) => ['event:' + key, name]));

  function option(text, value) {
    const node = el('option', text);
    node.value = value;
    return node;
  }

  function message(text, error = false) {
    const status = get('import-message');
    status.textContent = text;
    status.dataset.error = String(error);
  }

  function rows() {
    return batch.flatMap(file => file.rows);
  }

  function rowLabel(row) {
    const name = row.eventType || config.types[row.kind] || 'Choose event type';
    const alias = row.fields[row.mapping.id]?.value;
    return `${row.index + 1}. ${name} · ${alias ?? row.filename}`;
  }

  function fieldSelect(row, field) {
    const fieldLabel = ({id: 'Record ID', invoice_id: 'Parent invoice ID', journal_entry: 'Related journal ID'})[field] || label(field);
    const wrapper = el('label');
    const title = el('span', fieldLabel);
    title.id = 'mapping-label-' + field;
    const select = el('select');
    select.setAttribute('aria-labelledby', title.id);
    select.append(option('Unassigned', ''));
    const indexes = [...new Set([...importer.candidates(row, field).map(item => item.index), ...row.fields.keys()])];
    for (const index of indexes) {
      const {path, value} = row.fields[index];
      select.append(option(`${path.join(' › ')} · ${String(value).slice(0, 64)}`, index));
    }
    select.value = row.mapping[field] ?? '';
    select.addEventListener('change', () => {
      if (select.value === '') delete row.mapping[field];
      else row.mapping[field] = Number(select.value);
      refreshLabel(row);
      flagPending();
      showSinglePreview();
    });
    wrapper.append(title, select);
    return wrapper;
  }

  const missingType = row => !row.kind || (row.kind === 'event' && !row.eventType.trim());

  function flagPending(changed = true) {
    const all = rows();
    const missing = all.filter(missingType).length;
    const result = `${all.length} record${all.length === 1 ? '' : 's'} from ${batch.length} file${batch.length === 1 ? '' : 's'}`;
    message(missing ? `${result}. Choose a type for ${missing} unclassified record${missing === 1 ? '' : 's'}.` :
      `${result}. Review the event types and build the map.`);
    if (data.interactive_import) get('trace-origin').textContent = 'Showing the last built map. Build again to apply your edits.';
    if (changed && batch.length) {
      mapNeedsBuild = true;
      updateGapDownload();
    }
    get('build-import').disabled = busy || !all.length;
  }

  function refreshLabel(row) {
    for (const id of ['review-record', 'review-from', 'review-to']) {
      const offset = id === 'review-record' ? 0 : 1;
      const item = get(id).options[row.index + offset];
      if (item) item.textContent = rowLabel(row);
    }
    renderRelationships();
  }

  function renderRelationships() {
    const all = rows();
    const list = get('review-relationships');
    list.replaceChildren();
    for (const [index, relationship] of relationships.entries()) {
      const description = `${rowLabel(all[relationship.from])} → ${rowLabel(all[relationship.to])}`;
      const item = el('li', description);
      const remove = el('button', 'Remove', 'action');
      remove.type = 'button';
      remove.setAttribute('aria-label', `Remove relationship ${index + 1}`);
      remove.addEventListener('click', () => { relationships.splice(index, 1); renderRelationships(); flagPending(); });
      item.append(remove);
      list.append(item);
    }
  }

  function renderEditor() {
    const row = rows()[Number(reviewRecord.value)];
    const namedType = row?.kind === 'event' && [...namedTypes].find(([, name]) => name === row.eventType);
    roleSelect.value = namedType ? namedType[0] : row?.kind || '';
    get('event-name-row').hidden = !(row?.kind === 'event' || row?.eventType) || Boolean(namedType);
    get('event-name').value = row?.eventType || '';
    get('review-path').textContent = row ?
      `${row.filename} · ${row.path.length ? row.path.join(' › ') : 'Top-level record'} · ${row.basis}` : '';
    const fields = row?.kind ? importer.fieldNames(row.kind) : [];
    get('review-id').replaceChildren(...(fields.length ? [fieldSelect(row, 'id')] : []));
    get('review-fields').replaceChildren(...fields.slice(1).map(field => fieldSelect(row, field)));
    get('review-fields-details').hidden = !fields.length;
  }

  function renderQueue(preferredIndex) {
    const all = rows();
    get('import-editor').hidden = !batch.length;
    get('try-rollup').hidden = Boolean(batch.length);
    reviewRecord.replaceChildren(...all.map(row => option(rowLabel(row), row.index)));
    for (const [id, placeholder] of [['review-from', 'Select upstream record'], ['review-to', 'Select downstream record']]) {
      const select = get(id), value = select.value;
      select.replaceChildren(option(placeholder, ''), ...all.map(row => option(rowLabel(row), row.index)));
      if (value && Number(value) < all.length) select.value = value;
    }
    get('review-links').hidden = all.length < 2;
    if (preferredIndex !== undefined && all[preferredIndex]) reviewRecord.value = String(preferredIndex);
    renderEditor();
    renderRelationships();
  }

  function buildMap(selected, preview) {
    return importer.build(selected, batch.flatMap(file => file.links), relationships,
      batch.flatMap(file => file.lineage), batch.length, {preview});
  }

  function showSinglePreview({focus = false} = {}) {
    const all = rows();
    if (all.length !== 1) return false;
    const draft = all[0];
    let point = draft;
    if (missingType(draft)) {
      point = {...draft, eventType: '', basis: 'Cycle position needs confirmation'};
      importer.setKind(point, 'unmapped');
    }
    try {
      renderMap(buildMap([point], true));
      get('show-sample').hidden = false;
      get('trace-origin').textContent = 'Showing a suggested cycle from one record. Review its type or field mappings to refine it.';
      message('One record loaded. The billing cycle shows likely steps and open questions.');
      if (focus) {
        get('cycle-title').focus({preventScroll: true});
        get('entry-panel').scrollIntoView({block: 'start'});
      }
      return true;
    } catch (error) {
      message(error.message, true);
      return false;
    }
  }

  async function addFiles(selection) {
    if (!selection.length || busy) return;
    busy = true;
    get('try-rollup').disabled = get('choose-files').disabled = get('clear-import').disabled = get('build-import').disabled = true;
    let count = rows().length;
    const initialCount = count;
    const initialFiles = batch.length;
    const errors = [];
    for (const file of selection) {
      if (batch.length >= maxFiles) {
        errors.push(`Up to ${maxFiles} files per review.`);
        break;
      }
      try {
        if (file.size > maxBytes) throw Error('Choose a file smaller than 2 MB.');
        const input = importer.records(importer.parse(await file.text(), file.name));
        if (count + input.rows.length > maxRecords) throw Error('A review can contain up to 2,000 records.');
        const prepared = input.rows.map((row, index) => importer.prepare(row, file.name, count + index));
        batch.push({...input, rows: prepared});
        count += prepared.length;
      } catch (error) {
        const note = error instanceof SyntaxError ? 'Invalid JSON. Check that this is a JSON export.' : error.message;
        errors.push(`${file.name}: ${note}`);
      }
    }
    busy = false;
    get('try-rollup').disabled = get('choose-files').disabled = get('clear-import').disabled = false;
    renderQueue(rows().find(missingType)?.index ?? initialCount);
    flagPending(batch.length > initialFiles);
    const previewShown = batch.length > initialFiles && showSinglePreview({focus: count > initialCount});
    if (errors.length) message(`${errors.join(' ')}${rows().length ? ' Other loaded records are still available.' : ''}`, true);
    if (count > initialCount && !previewShown) reviewRecord.focus();
  }

  roleSelect.append(option('Choose event type', ''));
  for (const [kind, name] of Object.entries(config.types)) {
    if (kind !== 'unmapped' && kind !== 'event') roleSelect.append(option(name, kind));
  }
  const eventOptions = el('optgroup');
  eventOptions.label = 'Billing events';
  for (const [key, name] of namedTypes) eventOptions.append(option(name, key));
  eventOptions.append(option('Other event type', 'event'));
  roleSelect.append(eventOptions);
  get('try-rollup').addEventListener('click', () => {
    const rollup = {kind: 'aggregate', id: 'monthly-billing-rollup', measure: 'Original invoice total',
      total_amount: '1319.18', currency: 'USD', period_start: '2026-10-01', period_end: '2026-10-31'};
    void addFiles([new File([JSON.stringify(rollup)], 'sample-rollup.json', {type: 'application/json'})]);
  });
  get('choose-files').addEventListener('click', () => files.click());
  files.addEventListener('change', () => { const selected = [...files.files]; files.value = ''; void addFiles(selected); });
  for (const eventName of ['dragenter', 'dragover', 'dragleave', 'drop']) {
    drop.addEventListener(eventName, event => {
      event.preventDefault();
      drop.dataset.drag = String(eventName === 'dragenter' || eventName === 'dragover');
      if (eventName === 'drop') void addFiles([...event.dataTransfer.files]);
    });
  }
  // Keep a missed drop from navigating away from the current review.
  window.addEventListener('dragover', event => event.preventDefault());
  window.addEventListener('drop', event => event.preventDefault());
  reviewRecord.addEventListener('change', renderEditor);
  roleSelect.addEventListener('change', () => {
    const row = rows()[Number(reviewRecord.value)];
    if (!row) return;
    const selected = roleSelect.value;
    const kind = namedTypes.has(selected) ? 'event' : selected;
    if (row.kind !== kind) importer.setKind(row, kind);
    row.eventType = namedTypes.get(selected) || '';
    row.basis = 'Type selected for review';
    renderEditor();
    refreshLabel(row);
    flagPending();
    showSinglePreview();
  });
  get('event-name').addEventListener('input', event => {
    const row = rows()[Number(reviewRecord.value)];
    row.eventType = event.target.value;
    refreshLabel(row);
    flagPending();
    showSinglePreview();
  });
  get('add-relationship').addEventListener('click', () => {
    const left = get('review-from').value, right = get('review-to').value;
    if (!left || !right || left === right) {
      message('Choose two different records for this relationship.', true);
      return;
    }
    const from = Number(left), to = Number(right);
    if (!relationships.some(pair => pair.from === from && pair.to === to)) relationships.push({from, to});
    renderRelationships();
    flagPending();
  });
  get('build-import').addEventListener('click', () => {
    const all = rows();
    const unclassified = all.find(missingType);
    if (unclassified) {
      reviewRecord.value = String(unclassified.index);
      renderEditor();
      if (unclassified.kind) {
        message('Enter a name for this custom event type before building the map.', true);
        get('event-name').focus();
      } else {
        message('Choose an event type for this record before building the map.', true);
        roleSelect.focus();
      }
      return;
    }
    try {
      const report = buildMap(all, false);
      renderMap(report);
      get('trace-origin').textContent = 'Showing your imported records. The map traces relationships and flags gaps.';
      get('show-sample').hidden = false;
      message(`Built the map for ${all.length} imported record${all.length === 1 ? '' : 's'}.`);
      get('entries').focus();
    } catch (error) {
      message(error.message, true);
    }
  });
  get('show-sample').addEventListener('click', () => {
    renderMap(originalData);
    get('trace-origin').textContent = 'Showing the original map.';
    get('show-sample').hidden = true;
    get('choose-files').focus();
  });
  get('clear-import').addEventListener('click', () => {
    batch = [];
    relationships = [];
    renderQueue();
    renderMap(originalData);
    get('trace-origin').textContent = 'Showing the original map.';
    get('show-sample').hidden = true;
    message('Imported records cleared.');
    get('choose-files').focus();
  });
}
