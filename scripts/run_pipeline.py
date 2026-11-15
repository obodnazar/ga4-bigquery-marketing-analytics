#!/usr/bin/env python3
"""Build the GA4 marts in BigQuery, export them to CSV and rebuild the dashboard.

Usage:
    python3 scripts/run_pipeline.py --project YOUR_GCP_PROJECT
    python3 scripts/run_pipeline.py --project YOUR_GCP_PROJECT --dry-run   # bytes only

Needs the `bq` CLI, logged in to an account that can create datasets in
--project. The public source data is in the US, so the dataset is created in US.
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DATA_DIR = ROOT / "data"
MAX_BYTES = 50 * 1024**3  # hard stop per query; the BigQuery sandbox gives 1 TB/month free

EXPORTS = {
    "daily_channel": "SELECT * FROM `{p}.{d}.mart_daily_channel` ORDER BY session_date, channel_group, device_category",
    "funnel": "SELECT * FROM `{p}.{d}.mart_funnel` ORDER BY device_category, channel_group",
    "items": "SELECT * FROM `{p}.{d}.mart_items` WHERE item_revenue_usd > 0 ORDER BY item_revenue_usd DESC LIMIT 25",
    "cohorts": "SELECT * FROM `{p}.{d}.mart_cohorts` ORDER BY cohort_week, week_number",
    "dq_checks": "SELECT * FROM `{p}.{d}.dq_checks` ORDER BY check_order",
    # Distinct users cannot be summed, so export them pre-aggregated for every
    # filter combination the dashboard offers. NULL in a column means "all".
    "users": """
        SELECT channel_group, device_category, COUNT(DISTINCT user_pseudo_id) AS users
        FROM `{p}.{d}.int_sessions`
        GROUP BY GROUPING SETS ((channel_group, device_category), (channel_group), (device_category), ())
    """,
}


def bq(args, capture=False):
    cmd = ["bq", "--quiet"] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"bq failed: {' '.join(args[:3])}\n{result.stdout}\n{result.stderr}")
    return result.stdout if capture else None


def render(sql, a):
    return (sql.replace("{{project}}", a.project).replace("{{dataset}}", a.dataset)
               .replace("{{start}}", a.start).replace("{{end}}", a.end))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--dataset", default="ga4_portfolio")
    ap.add_argument("--start", default="20201101")
    ap.add_argument("--end", default="20210131")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    pid = f"--project_id={a.project}"

    if not a.dry_run:
        exists = subprocess.run(["bq", "--quiet", pid, "show", f"{a.project}:{a.dataset}"],
                                capture_output=True).returncode == 0
        if not exists:
            bq([pid, "--location=US", "mk", "--dataset", f"{a.project}:{a.dataset}"])
            print(f"created dataset {a.project}:{a.dataset}")

    for path in sorted(SQL_DIR.glob("*.sql")):
        query = render(path.read_text(), a)
        flags = [pid, "query", "--nouse_legacy_sql", f"--maximum_bytes_billed={MAX_BYTES}"]
        if a.dry_run:
            # Later models read tables that do not exist yet, so only 01 can be dry-run alone.
            out = subprocess.run(["bq", pid, "query", "--nouse_legacy_sql", "--dry_run", query],
                                 capture_output=True, text=True)
            print(path.name, (out.stdout or out.stderr).strip().splitlines()[-1])
            continue
        print(f"running {path.name} ...", flush=True)
        bq(flags + [query])

    if a.dry_run:
        return

    DATA_DIR.mkdir(exist_ok=True)
    for name, q in EXPORTS.items():
        csv = bq([pid, "query", "--nouse_legacy_sql", "--format=csv", "--max_rows=1000000",
                  q.format(p=a.project, d=a.dataset)], capture=True)
        (DATA_DIR / f"{name}.csv").write_text(csv)
        print(f"exported data/{name}.csv ({csv.count(chr(10)) - 1} rows)")

    subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "build_dashboard.py")], check=True)


if __name__ == "__main__":
    main()
