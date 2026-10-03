\set ON_ERROR_STOP on

-- 名称和编号取自工作簿；数量、价格、金额和日期均为新编的演示值。
INSERT INTO core.item (item_code,item_type,item_name,unit,supplier_part,category,reference_purchase_price,reference_sale_price,extra_unit_cost) VALUES
('P002','product','xt30总线中心板lite','pcs',NULL,NULL,NULL,35,0),
('M005','material','WAFER-GH1.25-4PLB','pcs',NULL,'connector',1.40,NULL,0),
('M003','material','XT30UPB-F30.G.Y','pcs',NULL,'connector',2.00,NULL,0),
('I001','other','卡夫特K5207工业胶粘剂','bottle',NULL,NULL,4.00,NULL,0);

INSERT INTO core.bom_revision (product_id,revision)
SELECT item_id,'demo-A' FROM core.item WHERE item_code='P002';
INSERT INTO core.bom_line (bom_id,line_no,component_id,quantity_per,raw_comment,designator,match_status)
SELECT b.bom_id,x.line_no,i.item_id,x.qty,x.comment,x.designator,'matched'
FROM core.bom_revision b
CROSS JOIN (VALUES (1,'M005',2.0::numeric,'WAFER-GH1.25-4PLB','U1'),
                   (2,'M003',1.0::numeric,'XT30UPB-F30.G.Y','CN2')) x(line_no,code,qty,comment,designator)
JOIN core.item i ON i.item_code=x.code;

INSERT INTO core.counterparty(name,party_type) VALUES ('演示客户','customer'),('演示供应商','supplier');
INSERT INTO core.project(project_code,project_name) VALUES ('METIS','Metis'),('GENERAL','通用经营');
INSERT INTO core.purpose(purpose_name) VALUES ('订单销售'),('原料采购'),('PCB/SMT'),('平台保证金'),('内部转账');

INSERT INTO finance.gl_account(account_code,account_name,account_class,normal_side,is_cash) VALUES
('1001','银行存款','asset','debit',true),
('1002','支付宝','asset','debit',true),
('1003','聚合算／微信收款','asset','debit',true),
('1401','原材料','asset','debit',false),
('1402','库存商品','asset','debit',false),
('1403','其他物品','asset','debit',false),
('1801','保证金','asset','debit',false),
('2001','应付账款','liability','credit',false),
('3001','期初投入资本','equity','credit',false),
('4001','主营业务收入','income','credit',false),
('5001','主营业务成本','expense','debit',false),
('5101','研发费用','expense','debit',false);

-- 沿用 account1.0 的“业务类型 → 借贷规则 → 现金流类别”设计。
INSERT INTO finance.posting_rule(event_type,debit_rule,credit_rule,cashflow_class) VALUES
('opening','target','3001','opening'),
('purchase_receipt','1401','2001','noncash'),
('purchase_payment','2001','source','operating'),
('sale_receipt','target','4001','operating'),
('sale_shipment','5001','1402','noncash'),
('internal_transfer','target','source','internal'),
('research_expense','5101','source','operating'),
('deposit_payment','1801','source','investing');

INSERT INTO ops.document(document_type,document_no,counterparty_id,document_date) VALUES
('purchase','DEMO-PUR-01',(SELECT counterparty_id FROM core.counterparty WHERE name='演示供应商'),'2026-09-03'),
('sales','DEMO-SALE-01',(SELECT counterparty_id FROM core.counterparty WHERE name='演示客户'),'2026-09-05');
INSERT INTO ops.document_line(document_id,line_no,item_id,quantity,unit_price)
SELECT d.document_id,1,i.item_id,30,1.40 FROM ops.document d CROSS JOIN core.item i
WHERE d.document_no='DEMO-PUR-01' AND i.item_code='M005';
INSERT INTO ops.document_line(document_id,line_no,item_id,quantity,unit_price)
SELECT d.document_id,1,i.item_id,2,35 FROM ops.document d CROSS JOIN core.item i
WHERE d.document_no='DEMO-SALE-01' AND i.item_code='P002';

INSERT INTO ops.production_plan(plan_name,plan_date,status) VALUES ('演示备货计划','2026-09-10','draft');
INSERT INTO ops.production_plan_line(plan_id,product_id,immediate_qty,reserve_qty)
SELECT p.plan_id,i.item_id,10,20 FROM ops.production_plan p CROSS JOIN core.item i WHERE i.item_code='P002';

INSERT INTO ops.business_event(event_code,event_date,event_type,amount,target_account_id,note) VALUES
('DEMO-O-BANK','2026-09-01','opening',3200,(SELECT account_id FROM finance.gl_account WHERE account_code='1001'),'演示期初银行'),
('DEMO-O-ALIPAY','2026-09-01','opening',400,(SELECT account_id FROM finance.gl_account WHERE account_code='1002'),'演示期初支付宝'),
('DEMO-O-M005','2026-09-01','opening',48,(SELECT account_id FROM finance.gl_account WHERE account_code='1401'),'演示期初物料 M005'),
('DEMO-O-M003','2026-09-01','opening',40,(SELECT account_id FROM finance.gl_account WHERE account_code='1401'),'演示期初物料 M003'),
('DEMO-O-P002','2026-09-01','opening',90,(SELECT account_id FROM finance.gl_account WHERE account_code='1402'),'演示期初成品'),
('DEMO-O-I001','2026-09-01','opening',20,(SELECT account_id FROM finance.gl_account WHERE account_code='1403'),'演示期初其他物品');

INSERT INTO ops.business_event(event_code,event_date,event_type,document_id,counterparty_id,project_id,purpose_id,source_account_id,target_account_id,amount,note)
SELECT x.code,x.day,x.kind,d.document_id,c.counterparty_id,p.project_id,u.purpose_id,
       sa.account_id,ta.account_id,x.amount,x.note
FROM (VALUES
 ('DEMO-RECEIPT','2026-09-03'::date,'purchase_receipt','DEMO-PUR-01','演示供应商','METIS','原料采购',NULL::text,NULL::text,42.00::numeric,'原料入库，形成应付'),
 ('DEMO-PAY','2026-09-04','purchase_payment','DEMO-PUR-01','演示供应商','METIS','原料采购','1001',NULL,42.00,'支付采购款'),
 ('DEMO-SHIP','2026-09-05','sale_shipment','DEMO-SALE-01','演示客户','GENERAL','订单销售',NULL,NULL,18.00,'成品出库并结转成本'),
 ('DEMO-SALE','2026-09-05','sale_receipt','DEMO-SALE-01','演示客户','GENERAL','订单销售',NULL,'1002',70.00,'支付宝收到货款'),
 ('DEMO-TRANSFER','2026-09-06','internal_transfer',NULL,NULL,'GENERAL','内部转账','1002','1001',100.00,'支付宝提现到银行'),
 ('DEMO-RND','2026-09-07','research_expense',NULL,'演示供应商','METIS','PCB/SMT','1002',NULL,25.00,'研发打样费用'),
 ('DEMO-DEPOSIT','2026-09-08','deposit_payment',NULL,'演示供应商','GENERAL','平台保证金','1002',NULL,60.00,'可退保证金')
) x(code,day,kind,doc_no,party,project,purpose,source_code,target_code,amount,note)
LEFT JOIN ops.document d ON d.document_no=x.doc_no
LEFT JOIN core.counterparty c ON c.name=x.party
LEFT JOIN core.project p ON p.project_code=x.project
LEFT JOIN core.purpose u ON u.purpose_name=x.purpose
LEFT JOIN finance.gl_account sa ON sa.account_code=x.source_code
LEFT JOIN finance.gl_account ta ON ta.account_code=x.target_code;

INSERT INTO ops.stock_movement(event_id,item_id,document_line_id,quantity_delta,value_delta)
SELECT e.event_id,i.item_id,dl.document_line_id,x.qty,x.value
FROM (VALUES
 ('DEMO-O-M005','M005',40.0::numeric,48.00::numeric,NULL::text),
 ('DEMO-O-M003','M003',20.0,40.00,NULL),
 ('DEMO-O-P002','P002',10.0,90.00,NULL),
 ('DEMO-O-I001','I001',5.0,20.00,NULL),
 ('DEMO-RECEIPT','M005',30.0,42.00,'DEMO-PUR-01'),
 ('DEMO-SHIP','P002',-2.0,-18.00,'DEMO-SALE-01')
) x(code,item_code,qty,value,doc_no)
JOIN ops.business_event e ON e.event_code=x.code
JOIN core.item i ON i.item_code=x.item_code
LEFT JOIN ops.document d ON d.document_no=x.doc_no
LEFT JOIN ops.document_line dl ON dl.document_id=d.document_id AND dl.item_id=i.item_id;

-- 先生成草稿凭证，再填明细，最后过账；过账触发器会拒绝不平衡凭证。
INSERT INTO finance.journal_entry(event_id,entry_date)
SELECT event_id,event_date FROM ops.business_event;

WITH pairs AS (
 SELECT e.event_id,e.event_code,e.amount,e.project_id,e.purpose_id,
        CASE WHEN r.debit_rule='target' THEN ta.account_code
             ELSE r.debit_rule END AS debit_code,
        CASE WHEN r.credit_rule='source' THEN sa.account_code ELSE r.credit_rule END AS credit_code
 FROM ops.business_event e JOIN finance.posting_rule r ON r.event_type=e.event_type
 LEFT JOIN finance.gl_account sa ON sa.account_id=e.source_account_id
 LEFT JOIN finance.gl_account ta ON ta.account_id=e.target_account_id
)
INSERT INTO finance.journal_line(entry_id,line_no,account_id,debit,credit,project_id,purpose_id)
SELECT j.entry_id,v.line_no,a.account_id,v.debit,v.credit,p.project_id,p.purpose_id
FROM pairs p JOIN finance.journal_entry j ON j.event_id=p.event_id
CROSS JOIN LATERAL (VALUES (1,p.debit_code,p.amount,0::numeric),
                           (2,p.credit_code,0::numeric,p.amount)) v(line_no,account_code,debit,credit)
JOIN finance.gl_account a ON a.account_code=v.account_code;

UPDATE finance.journal_entry SET status='posted' WHERE status='draft';
