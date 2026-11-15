-- Independent assertions against the disposable canonical fixture after dbt build.
DO $$
DECLARE
  invoice_total numeric; applied_total numeric; open_total numeric;
  gross_total numeric; fee_total numeric; net_total numeric;
  members bigint; conflicts bigint;
BEGIN
  IF current_database() <> 'advisor_economics_synthetic_test' THEN
    RAISE EXCEPTION 'Disposable test database required';
  END IF;
  SELECT sum(amount_minor), sum(applied_minor), sum(open_minor)
    INTO invoice_total, applied_total, open_total FROM analytics.fct_invoice_balance;
  SELECT sum(gross_minor), sum(fee_minor), sum(net_minor)
    INTO gross_total, fee_total, net_total FROM analytics.fct_bank_batch WHERE status='active';
  SELECT count(*) INTO members FROM analytics.bridge_bank_batch_receipt;
  SELECT count(*) INTO conflicts FROM analytics.fct_reconciliation_exceptions
    WHERE code IN ('REVERSED_RECEIPT_INVOICE_APPLICATION', 'REVERSED_RECEIPT_BANK_BATCH');
  IF ROW(invoice_total, applied_total, open_total, gross_total, fee_total, net_total, members, conflicts)
     IS DISTINCT FROM ROW(200000::numeric, 160000::numeric, 40000::numeric, 160000::numeric, 3000::numeric, 157000::numeric, 2::bigint, 2::bigint) THEN
    RAISE EXCEPTION 'Unexpected reconciliation values: invoice %, applied %, open %, gross %, fee %, net %, memberships %, conflicts %',
      invoice_total, applied_total, open_total, gross_total, fee_total, net_total, members, conflicts;
  END IF;
  RAISE NOTICE 'Verified invoices 200000/160000/40000, batch 160000/3000/157000, 2 memberships and 2 conflicts';
END $$;
