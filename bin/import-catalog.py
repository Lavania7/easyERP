"""Import only catalog identity fields from release2.0.xlsx into easyERP.

Stock, prices, BOM quantities, plans, and accounting test amounts are excluded.
Requires: pip install openpyxl
"""

import argparse
from pathlib import Path
import re

from openpyxl import load_workbook


SHEETS = (
    ("产品源数据表", "product", "P", 105),
    ("物料源数据表", "material", "M", 205),
    ("其他物品数据表", "other", "I", 205),
)


def sql_value(value):
    if value is None or value == "":
        return "NULL"
    clean = str(value).replace("\x00", "").replace("\r", " ").replace("\n", " ")
    return "'" + clean.replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workbook", type=Path, help="release2.0.xlsx path")
    parser.add_argument("--output", type=Path, default=Path("var/catalog_import.sql"))
    args = parser.parse_args()

    wb = load_workbook(args.workbook, read_only=True, data_only=False)
    rows = []
    codes = set()
    material_names = set()
    counts = {}
    for sheet_name, item_type, prefix, end_row in SHEETS:
        ws = wb[sheet_name]
        n = 0
        for cells in ws.iter_rows(min_row=6, max_row=end_row, values_only=True):
            code, name = cells[0], cells[1]
            if code is None and name is None:
                continue
            if not isinstance(code, str) or not re.fullmatch(prefix + r"[0-9]+", code):
                raise ValueError(f"{sheet_name}: invalid {prefix}ID {code!r}")
            if not isinstance(name, str) or not name.strip():
                raise ValueError(f"{sheet_name}: missing name for {code}")
            if code in codes:
                raise ValueError(f"duplicate item code: {code}")
            codes.add(code)
            if item_type == "material":
                if name in material_names:
                    raise ValueError(f"duplicate material name prevents exact BOM matching: {name}")
                material_names.add(name)
            supplier_part = cells[2] if item_type == "material" else None
            category = cells[3] if item_type == "material" else None
            rows.append((code, item_type, name, supplier_part, category))
            n += 1
        counts[sheet_name] = n

    sql = [
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "-- Names and IDs only. No quantities, prices, costs, or transactions are imported.",
    ]
    for code, item_type, name, supplier_part, category in rows:
        vals = ", ".join(sql_value(x) for x in (code, item_type, name, supplier_part, category))
        sql.append(
            "INSERT INTO core.item(item_code,item_type,item_name,supplier_part,category) "
            f"VALUES ({vals}) ON CONFLICT(item_code) DO UPDATE SET "
            "item_name=EXCLUDED.item_name, supplier_part=EXCLUDED.supplier_part, "
            "category=EXCLUDED.category WHERE core.item.item_type=EXCLUDED.item_type;"
        )
    sql.append("COMMIT;")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(sql) + "\n", encoding="utf-8")
    print("Catalog rows:", ", ".join(f"{name}={n}" for name, n in counts.items()))
    print("SQL generated:", args.output.resolve())
    print("No stock, price, BOM quantity, plan, or financial value was imported.")


if __name__ == "__main__":
    main()
