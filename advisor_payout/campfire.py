"""Offline Campfire-shaped fixture adapter; this module performs no HTTP calls.

Campfire's documented payment identifiers, timestamps and void field are used.
The sample cash-type allowlist and invoice/advisor mapping are our synthetic
policy, not verified facts about Savvy's configuration or Campfire's full enum.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
import json
from pathlib import Path
import re
from typing import Iterable, Mapping
from urllib.parse import urlencode


API_ORIGIN = "https://api.meetcampfire.com"
PAYMENTS_DOC = "https://docs.campfire.ai/api-reference/accounts-receivable/list-invoice-payments"
INVOICES_DOC = "https://docs.campfire.ai/api-reference/accounts-receivable/list-invoices"
SAMPLE_PATH = Path(__file__).resolve().parents[1] / "fixtures" / "campfire-sample.json"
MAX_CENTS = 10**14


class CampfireError(ValueError):
    """Invalid or unresolved source data; never a reason to invent an actual."""


def _text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 200:
        raise CampfireError(f"{field}: a nonempty bounded string is required")
    return value


def _id(value: object, field: str) -> str:
    if type(value) is int and value > 0:
        return str(value)
    if isinstance(value, str) and re.fullmatch(r"[0-9]{1,20}", value) and int(value) > 0:
        return str(int(value))
    raise CampfireError(f"{field}: a positive stable source ID is required")


def _date(value: object, field: str) -> date:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise CampfireError(f"{field}: use YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise CampfireError(f"{field}: invalid calendar date") from exc


def _timestamp(value: object, field: str) -> datetime:
    if not isinstance(value, str) or "T" not in value:
        raise CampfireError(f"{field}: an ISO timestamp with a timezone is required")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CampfireError(f"{field}: invalid timestamp") from exc
    if result.tzinfo is None:
        raise CampfireError(f"{field}: timezone is required")
    return result.astimezone(timezone.utc)


def _iso(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _cents(value: object, field: str) -> int:
    # Parse source JSON with parse_float=Decimal; a binary float has already
    # lost the source's decimal representation and is deliberately rejected.
    if type(value) not in (str, int, Decimal):
        raise CampfireError(f"{field}: decimal text or Decimal is required; floats are unsupported")
    try:
        amount = Decimal(value)
    except (InvalidOperation, ValueError) as exc:
        raise CampfireError(f"{field}: invalid decimal amount") from exc
    if not amount.is_finite() or amount < 0 or amount > Decimal(MAX_CENTS) / 100:
        raise CampfireError(f"{field}: nonnegative bounded amount required; reversals need explicit state")
    # Check the exact source digits *before* context-limited multiplication.
    # Otherwise a very small nonzero fractional cent could round away here.
    parts = amount.as_tuple()
    if parts.exponent < -2 and any(parts.digits[parts.exponent + 2:]):
        raise CampfireError(f"{field}: USD amounts must resolve to whole cents")
    cents = amount * 100
    if cents != cents.to_integral_value():
        raise CampfireError(f"{field}: USD amounts must resolve to whole cents")
    return int(cents)


def _required(record: Mapping, key: str) -> object:
    if key not in record:
        raise CampfireError(f"source record is missing {key}")
    return record[key]


def _latest_versions(rows: list[dict], scope_key: str) -> tuple[list[dict], list[dict]]:
    """Retain versions; collapse delivery repeats by source ID and revision.

    A newer void replaces the *current projection* of a payment. It never adds
    another payment, and the supplied earlier version remains in the output.
    Conflicting facts at one source revision cannot be resolved by arrival order.
    """
    grouped: dict[str, dict[str, dict]] = {}
    duplicates: dict[str, int] = {}
    for row in rows:
        versions = grouped.setdefault(row["id"], {})
        if versions and next(iter(versions.values()))[scope_key] != row[scope_key]:
            raise CampfireError("a stable source ID changed its mapped scope")
        revision = row["last_modified_at"]
        prior = versions.get(revision)
        if prior is not None:
            if prior != row:
                raise CampfireError("conflicting source facts share one ID and modification time")
            duplicates[row["id"]] = duplicates.get(row["id"], 0) + 1
        else:
            versions[revision] = row
    current, history = [], []
    for source_id in sorted(grouped, key=int):
        versions = sorted(grouped[source_id].values(), key=lambda row: _timestamp(row["last_modified_at"], "last_modified_at"))
        history.extend(dict(row) for row in versions)
        current.append({**versions[-1], "duplicate_observations": duplicates.get(source_id, 0), "superseded_versions": len(versions) - 1})
    return current, history


def normalize_invoice_payments(
    records: Iterable[Mapping],
    invoice_to_advisor: Mapping[str, str],
    *,
    cash_payment_types: Iterable[str] = (),
) -> dict:
    """Normalize supplied USD records without treating an unknown type as cash.

    CREDIT_MEMO is noncash. Cash classification requires an explicit allowlist;
    the bundled fixture's SYNTHETIC_CASH type is deliberately not a vendor enum.
    Campfire documents voided_date as the signal for voided/reversed payments.
    """
    mapping = {}
    for key, value in invoice_to_advisor.items():
        source_id = _id(key, "invoice mapping")
        if source_id in mapping:
            raise CampfireError("multiple mapping keys resolve to one source invoice")
        mapping[source_id] = _text(value, "advisor_id")
    cash_types = {_text(value, "cash_payment_type") for value in cash_payment_types}
    if "CREDIT_MEMO" in cash_types:
        raise CampfireError("CREDIT_MEMO cannot be classified as cash")
    rows = []
    for raw in records:
        invoice_id = _id(_required(raw, "invoice_id"), "invoice_id")
        if invoice_id not in mapping:
            raise CampfireError("payment invoice has no reviewed advisor mapping")
        currency = _required(raw, "currency")
        if currency != "USD":
            raise CampfireError("this adapter supports USD only; currency conversion is not inferred")
        kind = _text(_required(raw, "payment_type"), "payment_type")
        payment_date = _date(_required(raw, "payment_date"), "payment_date")
        void_value = _required(raw, "voided_date")
        voided = _date(void_value, "voided_date") if void_value is not None else None
        modified = _timestamp(_required(raw, "last_modified_at"), "last_modified_at")
        if voided and voided < payment_date:
            raise CampfireError("voided_date precedes payment_date")
        if modified.date() < payment_date or (voided and modified.date() < voided):
            raise CampfireError("source modification time precedes a reported payment or void")
        rows.append({
            "id": _id(_required(raw, "id"), "payment id"),
            "invoice_id": invoice_id,
            "advisor_id": mapping[invoice_id],
            "amount_cents": _cents(_required(raw, "amount"), "payment amount"),
            "currency": currency,
            "payment_date": payment_date.isoformat(),
            "payment_type": kind,
            "classification": "credit_memo" if kind == "CREDIT_MEMO" else "cash" if kind in cash_types else "unclassified",
            "state": "voided_or_reversed" if voided else "active",
            "voided_date": voided.isoformat() if voided else None,
            "last_modified_at": _iso(modified),
        })
    current, history = _latest_versions(rows, "invoice_id")
    return {"payments": current, "payment_versions": history}


def load_sample_snapshot() -> dict:
    """Read only the bundled synthetic fixture, preserving decimal amounts."""
    with SAMPLE_PATH.open(encoding="utf-8") as handle:
        return json.load(handle, parse_float=Decimal)


def summarize_snapshot(snapshot: Mapping, advisor_id: str) -> dict:
    """Build an advisor-scoped view from our explicitly synthetic snapshot."""
    if snapshot.get("source_mode") != "synthetic":
        raise CampfireError("this prototype accepts its synthetic snapshot contract only")
    if advisor_id not in snapshot["advisors"]:
        raise CampfireError("unknown advisor")
    period_start = _date(snapshot["period_start"], "period_start")
    period_end = _date(snapshot["period_end"], "period_end")
    as_of = _date(snapshot["as_of_date"], "as_of_date")
    if not period_start <= as_of <= period_end:
        raise CampfireError("as_of_date must be inside the fixture's reporting period")
    mapping, mapping_rows = {}, {}
    for row in snapshot["invoice_advisor_mappings"]:
        invoice_id = _id(row["invoice_id"], "mapped invoice_id")
        if invoice_id in mapping:
            raise CampfireError("an invoice has more than one advisor mapping")
        if row["advisor_id"] not in snapshot["advisors"]:
            raise CampfireError("invoice mapping names an unknown advisor")
        _text(row["evidence"], "mapping evidence")
        mapping[invoice_id], mapping_rows[invoice_id] = row["advisor_id"], row

    invoices = []
    for raw in snapshot["invoices"]:
        invoice_id = _id(raw["id"], "invoice id")
        if invoice_id not in mapping:
            raise CampfireError("invoice has no reviewed advisor mapping")
        if _id(raw["client"], "invoice client") != _id(mapping_rows[invoice_id]["client_id"], "mapping client"):
            raise CampfireError("invoice client does not match its advisor mapping")
        if raw["currency"] != "USD":
            raise CampfireError("this adapter supports USD only")
        if raw["period_start"] != period_start.isoformat() or raw["period_end"] != period_end.isoformat():
            raise CampfireError("invoice service period differs from the mapped forecast cohort")
        invoice_date = _date(raw["invoice_date"], "invoice_date")
        modified = _timestamp(raw["last_modified_at"], "last_modified_at")
        if invoice_date > as_of or modified.date() > as_of:
            raise CampfireError("invoice snapshot contains facts beyond its stated cutoff")
        voided = _date(raw["voided_date"], "invoice voided_date") if raw["voided_date"] is not None else None
        if modified.date() < invoice_date or (voided and (voided > as_of or modified.date() < voided)):
            raise CampfireError("invoice lifecycle dates disagree with the snapshot cutoff")
        if type(raw["is_deleted"]) is not bool:
            raise CampfireError("invoice is_deleted must be explicit")
        invoices.append({
            "id": invoice_id, "advisor_id": mapping[invoice_id],
            "invoice_number": _text(raw["invoice_number"], "invoice_number"),
            "invoice_date": invoice_date.isoformat(), "currency": "USD",
            "total_cents": _cents(raw["total_amount"], "invoice total"),
            "amount_paid_cents": _cents(raw["amount_paid"], "invoice paid"),
            "amount_due_cents": _cents(raw["amount_due"], "invoice due"),
            "state": "deleted" if raw["is_deleted"] else "voided" if voided else "active",
            "last_modified_at": _iso(modified),
        })
    current_invoices, _ = _latest_versions(invoices, "advisor_id")
    invoice_index = {row["id"]: row for row in current_invoices}
    if set(mapping) != set(invoice_index):
        raise CampfireError("invoice mappings and source invoice coverage differ")
    normalized = normalize_invoice_payments(snapshot["invoice_payments"], mapping, cash_payment_types=snapshot["cash_payment_types"])
    for row in normalized["payment_versions"]:
        if _timestamp(row["last_modified_at"], "last_modified_at").date() > as_of:
            raise CampfireError("payment snapshot contains revisions beyond its stated cutoff")
    selected_invoices = [row for row in current_invoices if row["advisor_id"] == advisor_id]
    selected_payments = []
    for row in normalized["payments"]:
        if row["advisor_id"] != advisor_id:
            continue
        in_window = period_start <= _date(row["payment_date"], "payment_date") <= as_of
        invoice_active = invoice_index[row["invoice_id"]]["state"] == "active"
        # Voiding an invoice does not establish that cash was refunded. Retain
        # an active cash record and flag its allocation for review separately.
        included = in_window and row["state"] == "active"
        selected_payments.append({**row, "included_in_observed_totals": included,
                                  "allocation_status": "mapped_active_invoice" if invoice_active else "inactive_invoice_requires_review",
                                  "exclusion": None if included else "voided_or_reversed" if row["state"] != "active" else "outside_cash_window"})
    included = [row for row in selected_payments if row["included_in_observed_totals"]]
    active_invoices = [row for row in selected_invoices if row["state"] == "active"]
    total = lambda category: sum(row["amount_cents"] for row in included if row["classification"] == category)
    cash, credits, unknown = total("cash"), total("credit_memo"), total("unclassified")
    inactive_allocations = sum(row["allocation_status"] == "inactive_invoice_requires_review" for row in included)
    notes = [
        "Synthetic data only. No Campfire or Savvy account is connected.",
        "Invoice-to-advisor and client mappings are explicit fixture policy; names never establish ownership.",
        "SYNTHETIC_CASH is a fixture-only classification, not a verified Campfire payment-type enum.",
        "Credit memos reduce a receivable but do not establish cash collected or an advisor payout.",
        "The sample maps one advisor per invoice and one USD service-period cohort. Shared invoices need a reviewed allocation rule.",
    ]
    if any(row["classification"] == "unclassified" for row in included):
        notes.append("Unclassified payments are excluded from cash; the collection comparison is incomplete.")
    if inactive_allocations:
        notes.append("Active payment records reference an inactive invoice. Cash remains observed; allocation needs review before a forecast comparison.")
    return {
        "source_mode": "synthetic", "connection": "not_connected", "provider": "Campfire",
        "metadata": {"advisor_id": advisor_id, "currency": "USD", "period_start": period_start.isoformat(),
                     "period_end": period_end.isoformat(), "as_of_date": as_of.isoformat(),
                     "source_snapshot_id": snapshot["snapshot_id"], "basis": "cash_payment_date_within_mapped_service_period_cohort"},
        "summary": {"invoice_count": len(active_invoices), "invoiced_cents": sum(row["total_cents"] for row in active_invoices),
                    "cash_collected_cents": cash, "credits_applied_cents": credits,
                    "unclassified_payments_cents": unknown,
                    "voided_or_reversed_cents": sum(row["amount_cents"] for row in selected_payments if row["state"] == "voided_or_reversed"),
                    "outstanding_invoice_cents": sum(row["amount_due_cents"] for row in active_invoices),
                    "duplicate_observations_ignored": sum(row["duplicate_observations"] for row in selected_payments),
                    "superseded_versions_retained": sum(row["superseded_versions"] for row in selected_payments),
                    "cash_classification_complete": all(row["classification"] != "unclassified" for row in included),
                    "inactive_invoice_payment_count": inactive_allocations,
                    "allocation_review_required": bool(inactive_allocations),
                    "source_coverage": "complete_for_synthetic_fixture_only"},
        "invoices": selected_invoices, "payments": selected_payments,
        "payment_versions": [row for row in normalized["payment_versions"] if row["advisor_id"] == advisor_id],
        "mapping_notes": notes,
        "documentation": [{"label": "Invoice payments", "url": PAYMENTS_DOC}, {"label": "Invoices", "url": INVOICES_DOC}],
    }


def sample_erp_status(advisor_id: str) -> dict:
    return summarize_snapshot(load_sample_snapshot(), advisor_id)


def reconcile_cash_forecast(status: Mapping, forecast_cash_cents: int, *, period_start: str, period_end: str, currency: str, collection_through_date: str | None = None) -> dict:
    """Compare one service cohort's observed cash with a dated collection target.

    This is a progress gap, never a final variance, approved payable or posting.
    Credits are intentionally absent from cash. Unknown classifications withhold
    the gap rather than presenting the known cash subtotal as complete actuals.
    """
    if type(forecast_cash_cents) is not int or not 0 <= forecast_cash_cents <= MAX_CENTS:
        raise CampfireError("forecast_cash_cents must be a bounded nonnegative integer")
    meta = status["metadata"]
    if (period_start, period_end, currency) != (meta["period_start"], meta["period_end"], meta["currency"]):
        raise CampfireError("forecast and observed cash scopes do not match")
    known_cash = status["summary"]["cash_collected_cents"]
    complete = status["summary"]["cash_classification_complete"]
    allocation_review = status["summary"]["allocation_review_required"]
    if collection_through_date is not None and _date(collection_through_date, "collection_through_date") < _date(meta["as_of_date"], "as_of_date"):
        raise CampfireError("collection target cannot precede the observed cash cutoff")
    ready = complete and not allocation_review and collection_through_date is not None
    comparison_status = "classification_incomplete" if not complete else "allocation_review_required" if allocation_review else "collection_horizon_required" if collection_through_date is None else "illustrative_progress_comparison"
    return {"comparison": "observed_to_date_vs_forecast_collection_target", "source_mode": status["source_mode"],
            "advisor_id": meta["advisor_id"], "currency": currency, "as_of_date": meta["as_of_date"],
            "service_period_start": period_start, "service_period_end": period_end,
            "collection_through_date": collection_through_date, "allocation_review_required": allocation_review,
            "observed_cash_cents": known_cash, "full_period_forecast_cash_cents": forecast_cash_cents,
            "gap_to_full_period_forecast_cents": forecast_cash_cents - known_cash if ready else None,
            "final_variance_cents": None, "posting_enabled": False,
            "status": comparison_status,
            "explanation": "Observed cash is through the stated cutoff. The forecast covers the service period with collections expected through its separate target date. The gap is not a final variance or payout authorization."}


def plan_read_requests(since: str | None = None) -> dict:
    """Describe documented GET reads without executing them or reading secrets."""
    payment_params: dict[str, object] = {"cursor": "", "limit": 100}
    if since is not None:
        if not isinstance(since, str):
            raise CampfireError("since must be an ISO date or timestamp")
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", since):
            _date(since, "since")
            payment_params["last_modified_at__gte"] = since
        else:
            payment_params["last_modified_at__gte"] = _iso(_timestamp(since, "since"))
    requests = []
    for path, params, documentation in [
        ("/coa/api/v1/invoice", {"limit": 100, "offset": 0}, INVOICES_DOC),
        ("/coa/api/v1/invoice-payments", payment_params, PAYMENTS_DOC),
    ]:
        requests.append({"method": "GET", "path": path, "params": params,
                         "url": API_ORIGIN + path + "?" + urlencode(params), "documentation": documentation})
    return {"mode": "plan_only", "connection": "not_connected", "network_execution": False,
            "requests": requests,
            "constraints": ["Never set the invoice download parameter: it triggers an email export.",
                            "Keep voided payments in reads; later voids must replace the current projection of the same stable ID.",
                            "Follow the API's opaque next links only after validating the expected HTTPS origin and path.",
                            "A future live importer needs pagination, retained source versions, client/advisor mapping and approved cash-type evidence.",
                            "Invoice reads use a full paged snapshot here; no undocumented modification-time filter is invented."]}
