\set ON_ERROR_STOP on

DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM report.unbalanced_journal) THEN
   RAISE EXCEPTION 'unbalanced journal entry';
 END IF;
 IF EXISTS (SELECT 1 FROM report.inventory_gl_difference WHERE difference <> 0) THEN
   RAISE EXCEPTION 'inventory and general ledger disagree';
 END IF;
 IF EXISTS (SELECT 1 FROM report.balance_sheet_check WHERE difference <> 0) THEN
   RAISE EXCEPTION 'balance sheet does not balance';
 END IF;
 IF (SELECT suggested_purchase FROM report.material_requirement WHERE item_code='M003') <> 10 THEN
   RAISE EXCEPTION 'material requirement calculation failed';
 END IF;
 IF (SELECT profit FROM report.income_statement) <> 27 THEN
   RAISE EXCEPTION 'income statement calculation failed';
 END IF;
 IF (SELECT SUM(net_cash) FROM report.cash_flow) <> -57 THEN
   RAISE EXCEPTION 'cash flow calculation failed';
 END IF;
 RAISE NOTICE 'easyERP demo checks passed';
END $$;

SELECT item_code,item_name,quantity,carrying_value FROM report.stock_balance ORDER BY item_code;
SELECT item_code,gross_required,on_hand,suggested_purchase,estimated_spend FROM report.material_requirement ORDER BY item_code;
SELECT account_code,account_name,debit_balance FROM report.account_balance ORDER BY account_code;
SELECT * FROM report.income_statement;
SELECT * FROM report.balance_sheet_check;
SELECT * FROM report.cash_flow ORDER BY cashflow_class;
SELECT * FROM report.inventory_gl_difference ORDER BY class_code;
