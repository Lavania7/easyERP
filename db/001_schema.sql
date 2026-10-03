\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS report;

CREATE TABLE core.item (
    item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_code text NOT NULL UNIQUE CHECK (item_code ~ '^[PMI][0-9]+$'),
    item_type text NOT NULL CHECK (item_type IN ('product','material','other')),
    item_name text NOT NULL,
    unit text NOT NULL DEFAULT 'pcs',
    supplier_part text,
    category text,
    reference_purchase_price numeric(18,4) CHECK (reference_purchase_price >= 0),
    reference_sale_price numeric(18,4) CHECK (reference_sale_price >= 0),
    extra_unit_cost numeric(18,4) NOT NULL DEFAULT 0 CHECK (extra_unit_cost >= 0),
    active boolean NOT NULL DEFAULT true,
    CHECK ((item_type = 'product' AND item_code LIKE 'P%') OR
           (item_type = 'material' AND item_code LIKE 'M%') OR
           (item_type = 'other' AND item_code LIKE 'I%'))
);
CREATE UNIQUE INDEX one_mid_per_material_name ON core.item(item_name) WHERE item_type='material';

CREATE TABLE core.bom_revision (
    bom_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES core.item(item_id),
    revision text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    UNIQUE (product_id, revision)
);

CREATE UNIQUE INDEX one_active_bom_per_product ON core.bom_revision(product_id) WHERE active;

CREATE TABLE core.bom_line (
    bom_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_id bigint NOT NULL REFERENCES core.bom_revision(bom_id) ON DELETE CASCADE,
    line_no integer NOT NULL CHECK (line_no > 0),
    component_id bigint REFERENCES core.item(item_id),
    quantity_per numeric(18,4) NOT NULL CHECK (quantity_per > 0),
    raw_comment text NOT NULL,
    designator text,
    footprint text,
    supplier_part text,
    match_status text NOT NULL CHECK (match_status IN ('matched','needs_material')),
    UNIQUE (bom_id, line_no),
    CHECK ((match_status = 'matched' AND component_id IS NOT NULL) OR
           (match_status = 'needs_material' AND component_id IS NULL))
);

CREATE FUNCTION core.validate_bom_item_types() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT item_type FROM core.item WHERE item_id=(SELECT product_id FROM core.bom_revision WHERE bom_id=NEW.bom_id)) <> 'product' THEN
        RAISE EXCEPTION 'BOM parent must be a product';
    END IF;
    IF NEW.component_id IS NOT NULL AND (SELECT item_type FROM core.item WHERE item_id=NEW.component_id) <> 'material' THEN
        RAISE EXCEPTION 'BOM component must be a material';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER validate_bom_item_types BEFORE INSERT OR UPDATE ON core.bom_line
FOR EACH ROW EXECUTE FUNCTION core.validate_bom_item_types();

CREATE TABLE core.counterparty (
    counterparty_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE,
    party_type text NOT NULL CHECK (party_type IN ('customer','supplier','both','other'))
);
CREATE TABLE core.project (
    project_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_code text NOT NULL UNIQUE,
    project_name text NOT NULL
);
CREATE TABLE core.purpose (
    purpose_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purpose_name text NOT NULL UNIQUE
);

CREATE TABLE finance.gl_account (
    account_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_code text NOT NULL UNIQUE,
    account_name text NOT NULL,
    account_class text NOT NULL CHECK (account_class IN ('asset','liability','equity','income','expense')),
    normal_side text NOT NULL CHECK (normal_side IN ('debit','credit')),
    is_cash boolean NOT NULL DEFAULT false
);

CREATE TABLE finance.posting_rule (
    event_type text PRIMARY KEY,
    debit_rule text NOT NULL,
    credit_rule text NOT NULL,
    cashflow_class text NOT NULL CHECK (cashflow_class IN ('opening','operating','investing','financing','internal','noncash')),
    CHECK (debit_rule <> '' AND credit_rule <> '')
);

CREATE TABLE ops.document (
    document_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_type text NOT NULL CHECK (document_type IN ('sales','purchase','production')),
    document_no text NOT NULL,
    counterparty_id bigint REFERENCES core.counterparty(counterparty_id),
    document_date date NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','cancelled')),
    UNIQUE (document_type, document_no)
);

CREATE TABLE ops.document_line (
    document_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_id bigint NOT NULL REFERENCES ops.document(document_id) ON DELETE CASCADE,
    line_no integer NOT NULL CHECK (line_no > 0),
    item_id bigint NOT NULL REFERENCES core.item(item_id),
    quantity numeric(18,4) NOT NULL CHECK (quantity > 0),
    unit_price numeric(18,4) CHECK (unit_price >= 0),
    UNIQUE (document_id, line_no)
);

CREATE TABLE ops.business_event (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_code text NOT NULL UNIQUE,
    event_date date NOT NULL,
    event_type text NOT NULL REFERENCES finance.posting_rule(event_type),
    document_id bigint REFERENCES ops.document(document_id),
    counterparty_id bigint REFERENCES core.counterparty(counterparty_id),
    project_id bigint REFERENCES core.project(project_id),
    purpose_id bigint REFERENCES core.purpose(purpose_id),
    source_account_id bigint REFERENCES finance.gl_account(account_id),
    target_account_id bigint REFERENCES finance.gl_account(account_id),
    amount numeric(18,2) CHECK (amount > 0),
    note text,
    source_workbook text,
    source_sheet text,
    source_key text,
    UNIQUE (source_workbook, source_sheet, source_key)
);

CREATE TABLE ops.stock_movement (
    movement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id bigint NOT NULL REFERENCES ops.business_event(event_id),
    item_id bigint NOT NULL REFERENCES core.item(item_id),
    document_line_id bigint REFERENCES ops.document_line(document_line_id),
    quantity_delta numeric(18,4) NOT NULL CHECK (quantity_delta <> 0),
    value_delta numeric(18,2) NOT NULL,
    CHECK ((quantity_delta > 0 AND value_delta >= 0) OR
           (quantity_delta < 0 AND value_delta <= 0))
);

CREATE TABLE ops.production_plan (
    plan_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_name text NOT NULL UNIQUE,
    plan_date date NOT NULL,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','closed'))
);
CREATE TABLE ops.production_plan_line (
    plan_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_id bigint NOT NULL REFERENCES ops.production_plan(plan_id) ON DELETE CASCADE,
    product_id bigint NOT NULL REFERENCES core.item(item_id),
    immediate_qty numeric(18,4) NOT NULL DEFAULT 0 CHECK (immediate_qty >= 0),
    reserve_qty numeric(18,4) NOT NULL DEFAULT 0 CHECK (reserve_qty >= 0),
    UNIQUE (plan_id, product_id)
);

CREATE TABLE finance.journal_entry (
    entry_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id bigint NOT NULL UNIQUE REFERENCES ops.business_event(event_id),
    entry_date date NOT NULL,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted'))
);

CREATE TABLE finance.journal_line (
    line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entry_id bigint NOT NULL REFERENCES finance.journal_entry(entry_id),
    line_no integer NOT NULL CHECK (line_no > 0),
    account_id bigint NOT NULL REFERENCES finance.gl_account(account_id),
    debit numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    project_id bigint REFERENCES core.project(project_id),
    purpose_id bigint REFERENCES core.purpose(purpose_id),
    UNIQUE (entry_id, line_no),
    CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);

CREATE FUNCTION finance.check_posted_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE deb numeric(18,2); cred numeric(18,2); line_count integer;
BEGIN
    IF NEW.status = 'posted' THEN
        SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0), COUNT(*)
        INTO deb, cred, line_count FROM finance.journal_line WHERE entry_id = NEW.entry_id;
        IF line_count < 2 OR deb <> cred THEN
            RAISE EXCEPTION 'entry % is not balanced: debit %, credit %', NEW.entry_id, deb, cred;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER check_posted_entry BEFORE INSERT OR UPDATE OF status ON finance.journal_entry
FOR EACH ROW EXECUTE FUNCTION finance.check_posted_entry();

CREATE FUNCTION finance.lock_posted_lines() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE entry_status text;
BEGIN
    SELECT status INTO entry_status FROM finance.journal_entry
    WHERE entry_id = COALESCE(NEW.entry_id, OLD.entry_id);
    IF entry_status = 'posted' THEN
        RAISE EXCEPTION 'posted journal lines are immutable; create a reversing event';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER lock_posted_lines BEFORE INSERT OR UPDATE OR DELETE ON finance.journal_line
FOR EACH ROW EXECUTE FUNCTION finance.lock_posted_lines();

CREATE VIEW report.stock_balance AS
SELECT i.item_id, i.item_code, i.item_type, i.item_name,
       SUM(m.quantity_delta)::numeric(18,4) AS quantity,
       SUM(m.value_delta)::numeric(18,2) AS carrying_value
FROM core.item i LEFT JOIN ops.stock_movement m ON m.item_id = i.item_id
GROUP BY i.item_id;

CREATE VIEW report.account_balance AS
SELECT a.account_code, a.account_name, a.account_class, a.is_cash,
       COALESCE(SUM(CASE WHEN e.status = 'posted' THEN l.debit-l.credit ELSE 0 END),0)::numeric(18,2) AS debit_balance
FROM finance.gl_account a LEFT JOIN finance.journal_line l ON l.account_id = a.account_id
LEFT JOIN finance.journal_entry e ON e.entry_id = l.entry_id
GROUP BY a.account_id;

CREATE VIEW report.bom_unit_cost AS
SELECT b.product_id, i.item_code AS product_code,
       COUNT(*) FILTER (WHERE l.match_status <> 'matched' OR c.reference_purchase_price IS NULL) AS unresolved_lines,
       CASE WHEN COUNT(*) FILTER (WHERE l.match_status <> 'matched' OR c.reference_purchase_price IS NULL) = 0
            THEN SUM(l.quantity_per*c.reference_purchase_price)+i.extra_unit_cost END AS reference_unit_cost
FROM core.bom_revision b JOIN core.item i ON i.item_id = b.product_id
JOIN core.bom_line l ON l.bom_id = b.bom_id
LEFT JOIN core.item c ON c.item_id = l.component_id
WHERE b.active GROUP BY b.product_id, i.item_code, i.extra_unit_cost;

CREATE VIEW report.material_requirement AS
WITH demand AS (
    SELECT l.component_id AS item_id,
           SUM(l.quantity_per*(p.immediate_qty+p.reserve_qty)) AS gross_required
    FROM ops.production_plan_line p JOIN core.bom_revision b ON b.product_id = p.product_id AND b.active
    JOIN core.bom_line l ON l.bom_id = b.bom_id
    JOIN ops.production_plan h ON h.plan_id = p.plan_id
    WHERE h.status <> 'closed' AND l.match_status = 'matched'
    GROUP BY l.component_id
)
SELECT i.item_code, i.item_name, COALESCE(d.gross_required,0)::numeric(18,4) AS gross_required,
       s.quantity AS on_hand,
       CASE WHEN s.quantity IS NOT NULL THEN
           GREATEST(0,COALESCE(d.gross_required,0)-s.quantity)::numeric(18,4) END AS suggested_purchase,
       CASE WHEN i.reference_purchase_price IS NOT NULL AND s.quantity IS NOT NULL THEN
           (GREATEST(0,COALESCE(d.gross_required,0)-s.quantity)*i.reference_purchase_price)::numeric(18,2) END AS estimated_spend
FROM core.item i JOIN report.stock_balance s ON s.item_id = i.item_id
LEFT JOIN demand d ON d.item_id = i.item_id WHERE i.item_type = 'material';

CREATE VIEW report.unbalanced_journal AS
SELECT e.entry_id, e.status, SUM(l.debit) AS debit, SUM(l.credit) AS credit
FROM finance.journal_entry e JOIN finance.journal_line l ON l.entry_id = e.entry_id
GROUP BY e.entry_id, e.status HAVING SUM(l.debit) <> SUM(l.credit);

CREATE VIEW report.inventory_gl_difference AS
SELECT class_code, stock_value, gl_value, uninitialized_items,
       (stock_value-gl_value)::numeric(18,2) AS difference
FROM (
    SELECT CASE item_type WHEN 'material' THEN '1401' WHEN 'product' THEN '1402' ELSE '1403' END class_code,
           SUM(carrying_value)::numeric(18,2) stock_value,
           COUNT(*) FILTER (WHERE quantity IS NULL) AS uninitialized_items
    FROM report.stock_balance GROUP BY item_type
) s JOIN (SELECT account_code, debit_balance AS gl_value FROM report.account_balance) g ON g.account_code=s.class_code;

CREATE VIEW report.income_statement AS
SELECT COALESCE(SUM(CASE WHEN account_class='income' THEN -debit_balance ELSE 0 END),0)::numeric(18,2) AS revenue,
       COALESCE(SUM(CASE WHEN account_class='expense' THEN debit_balance ELSE 0 END),0)::numeric(18,2) AS expenses,
       COALESCE(SUM(CASE WHEN account_class='income' THEN -debit_balance
                         WHEN account_class='expense' THEN -debit_balance ELSE 0 END),0)::numeric(18,2) AS profit
FROM report.account_balance;

CREATE VIEW report.balance_sheet_check AS
SELECT assets, liabilities, equity, profit,
       (assets-liabilities-equity-profit)::numeric(18,2) AS difference
FROM (
    SELECT COALESCE(SUM(CASE WHEN account_class='asset' THEN debit_balance ELSE 0 END),0)::numeric(18,2) assets,
           COALESCE(SUM(CASE WHEN account_class='liability' THEN -debit_balance ELSE 0 END),0)::numeric(18,2) liabilities,
           COALESCE(SUM(CASE WHEN account_class='equity' THEN -debit_balance ELSE 0 END),0)::numeric(18,2) equity
    FROM report.account_balance
) b CROSS JOIN report.income_statement;

CREATE VIEW report.cash_flow AS
SELECT r.cashflow_class,
       COALESCE(SUM(l.debit-l.credit),0)::numeric(18,2) AS net_cash
FROM finance.journal_line l JOIN finance.journal_entry j ON j.entry_id=l.entry_id AND j.status='posted'
JOIN finance.gl_account a ON a.account_id=l.account_id AND a.is_cash
JOIN ops.business_event e ON e.event_id=j.event_id
JOIN finance.posting_rule r ON r.event_type=e.event_type
WHERE r.cashflow_class NOT IN ('opening','internal','noncash')
GROUP BY r.cashflow_class;
