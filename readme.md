# easyERP PostgreSQL demo

这个 demo 使用独立的本地 PostgreSQL 18 数据目录。工作簿仍是参考和可继续使用的界面；演示库不修改任何 `.xlsx`。`002_demo.sql` 沿用产品/物料/其他物品的编号与名称，以及 `account.md` 的资金账户和业务分类；其中日期、数量、单价和金额是新编的演示值。

## 目录

- `001_schema.sql`：主数据、BOM、单据、业务事件、库存流水、会计分录和报表视图。
- `002_demo.sql`：可重建的合成演示数据。
- `003_checks.sql`：借贷平衡、库存与总账、资产负债、利润和现金流核对。
- `../bin/easyerp-db.ps1`：启动、停止、重建与检查本地数据库。
- `../var/pgdata`：本地数据库文件，不进入版本控制。

## 运行

在 PowerShell 中，从项目根目录执行：

```powershell
.\bin\easyerp-db.ps1 init
.\bin\easyerp-db.ps1 start
.\bin\easyerp-db.ps1 reset
.\bin\easyerp-db.ps1 check
```

连接参数：`127.0.0.1:55432`，数据库 `easyerp_demo`，用户 `erp_demo`。此独立 demo 仅监听回环地址，本机连接使用 `trust` 认证；它不用于生产数据。交互查询：

```powershell
.\bin\easyerp-db.ps1 shell
```

结束时运行 `.\bin\easyerp-db.ps1 stop`。`reset` 会删除并重建 **easyerp_demo** 这个演示数据库，不触碰其他数据库或 Excel 文件。若本机端口已占用，可设置 `EASYERP_PG_PORT` 后重新 `init/start`；初始化过的数据目录中端口由启动参数控制。

## 数据边界

- `item` 的 PID/MID/IID 是外部编号；数据库内部关系使用数字主键。业务 ID 另有 `event_code`，所以产品 P001 与财务 P001 不会撞键。
- `bom_line.raw_comment` 保留外部 BOM 原文，`component_id` 只在唯一匹配后填写。缺料号或价格的行不能被当作零成本。
- `production_plan` 是计划，不能直接改变库存。只有实际入库、出库事件写入 `stock_movement`。
- `journal_line` 是资金和其他会计科目的底账。内部转账一借一贷，现金流视图排除它；库存数量来自 `stock_movement`，库存价值必须与 1401/1402/1403 对账。
- 仅导入编号与名称的物品没有期初流水，库存视图显示空值（未知），不会伪装成零库存；核对视图显示尚未初始化的物品数量。
- Excel 导入时，先导入编号和名称；BOM 原文、数量与规则须另外核对。工作簿里的测试库存、价格、金额与交易不自动迁入。真实启用前另定期初日，逐项确认数量与估值。

## Excel 名称导入

`bin/import-catalog.py` 读取 `release2.0.xlsx` 的 PID/MID/IID、名称、物料供应商料号和类型，生成可检查的 SQL 文件。需要 Python 与 `bin/requirements.txt` 中的 `openpyxl`。它**不导入**工作簿中的库存、价格、BOM 数量、生产计划或财务测试记录。

```powershell
python -m pip install -r .\bin\requirements.txt
python .\bin\import-catalog.py .\release2.0.xlsx
Get-Content .\var\catalog_import.sql -TotalCount 10
$env:PGHOST='127.0.0.1'; $env:PGPORT='55432'; $env:PGUSER='erp_demo'
& 'E:\PostgreSQL18\bin\psql.exe' -d easyerp_demo -v ON_ERROR_STOP=1 -f .\var\catalog_import.sql
```

导入是按编号更新名称和分类，可重复执行。BOM 原始行与真实数量要在确认后单独导入；此 demo 的两条 BOM 和所有金额是合成示例。
