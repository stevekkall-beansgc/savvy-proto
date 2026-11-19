'use strict';

const tracePreviews = (() => {
  const own = (value, key) => Object.hasOwn(value, key);
  const labels = {
    id:'Record ID', source_id:'Source record ID', invoice_id:'Invoice ID',
    invoice_line_id:'Invoice line ID', gl_account_code:'GL account code',
    amount_minor:'Amount in minor units', debit_minor:'Debit in minor units', credit_minor:'Credit in minor units',
    event_type:'Event type', package_id:'Accounting package ID',
  };
  const label = field => labels[field] || field.replaceAll('_', ' ').replace(/^./, char => char.toUpperCase()).replace(/\bid\b/g, 'ID');
  const scalar = value => typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value)) ||
    (typeof value === 'string' && value.trim()) ? String(value).slice(0, 160) : undefined;

  function capture(record, kind, profiles) {
    const captureFields = (value, fields) => {
      const captured = {};
      for (const key of fields) {
        const text = scalar(value[key]);
        if (text !== undefined) captured[key] = text;
      }
      return captured;
    };
    const fields = captureFields(record, profiles.fields[kind] || []);
    const sections = {};
    for (const section of profiles.sections_by_type[kind] || []) {
      const values = record[section];
      if (!Array.isArray(values)) continue;
      const rows = values.slice(0, 12).filter(value => value && typeof value === 'object' && !Array.isArray(value))
        .map(value => captureFields(value, profiles.sections[section])).filter(row => Object.keys(row).length);
      sections[section] = {rows, total:values.length};
    }
    return {fields, sections};
  }

  function model(kind, entry, profiles) {
    const supplied = entry && entry.state !== 'reference only';
    const fields = {...entry?.preview?.fields, ...entry?.evidence};
    if (entry?.id) fields.id = entry.id;
    if (entry?.declared_dimensions?.length) fields.columns = entry.declared_dimensions.join(', ');
    const keys = new Set(['id', ...(profiles.fields[kind] || []), ...Object.keys(fields)]);
    const rows = [...keys].map(key => {
      const value = fields[key];
      if (value === undefined) return {field:label(key), status:supplied ? 'Not supplied' : 'To confirm'};
      const status = key === 'columns' ? 'Declared' : key === 'event_type' && entry?.reviewer_event_label ? 'Reviewer label' :
        supplied ? 'Supplied' : 'Reference';
      return {field:label(key), value, status};
    });
    const sections = (profiles.sections_by_type[kind] || []).map(section => {
      const known = entry?.preview?.sections?.[section];
      const columns = profiles.sections[section].filter(key => known?.rows.some(row => own(row, key)));
      return {title:label(section), columns:columns.map(label),
        rows:known?.rows.map(row => columns.map(key => row[key])) || [], total:known?.total || 0};
    });
    return {rows, sections};
  }

  return {capture, model};
})();

if (typeof module !== 'undefined') module.exports = tracePreviews;
