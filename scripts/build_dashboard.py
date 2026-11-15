#!/usr/bin/env python3
"""Embed the exported CSVs from data/ into dashboard/template.html -> dashboard/index.html.

Usage: python3 scripts/build_dashboard.py [--data DIR] [--out FILE]
"""
import argparse
import csv
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAMES = ["daily_channel", "funnel", "items", "cohorts", "dq_checks", "users"]
TEXT_COLUMNS = {"session_date", "channel_group", "device_category", "item_name",
                "item_category", "cohort_week", "check_name"}


def convert(key, value):
    if key in TEXT_COLUMNS:
        return None if value in ("", "NULL") else value
    if value in ("", "NULL"):
        return 0
    number = float(value)
    return int(number) if number.is_integer() else number


def load(path):
    with path.open(newline="") as f:
        return [{k: convert(k, v) for k, v in row.items()} for row in csv.DictReader(f)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(ROOT / "data"))
    ap.add_argument("--out", default=str(ROOT / "dashboard" / "index.html"))
    a = ap.parse_args()

    data = {name: load(pathlib.Path(a.data) / f"{name}.csv") for name in NAMES}
    payload = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
    template = (ROOT / "dashboard" / "template.html").read_text()
    pathlib.Path(a.out).write_text(template.replace("/*__DATA__*/", payload))
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
