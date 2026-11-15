#!/usr/bin/env python3
"""Generate a Looker Studio Linking API URL that copies the master template
(docs/looker-template-spec.md) and points every data source at one client's marts.

BigQuery (normal client work):
    python3 scripts/looker_link.py --template REPORT_ID \
        --project client-gcp-project --dataset ga4_marts --name "Acme · GA4 performance"

Google Sheets (marts exported to a spreadsheet, one tab per mart):
    python3 scripts/looker_link.py --template REPORT_ID --sheets SPREADSHEET_ID \
        --gid daily=0 --gid funnel=1267068877 --gid items=1786191650 --gid dq=1064142588

From a JSON file (keys match the long option names, e.g. {"template": "...", "project": "..."}):
    python3 scripts/looker_link.py --config clients/acme.json

Open the printed URL while signed in to the account that should own the copy.
Only the standard library is used.
"""
import argparse
import json
import re
import sys
from urllib.parse import quote, urlencode

BASE = "https://lookerstudio.google.com/reporting/create"

# Template alias -> mart table. Must match docs/looker-template-spec.md, section 1.
TABLES = {
    "daily": "mart_daily_channel",
    "funnel": "mart_funnel",
    "items": "mart_items",
    "dq": "dq_checks",
}
LABELS = {
    "daily": "Daily channel",
    "funnel": "Funnel",
    "items": "Items",
    "dq": "Data quality checks",
    "users": "Users (sessions)",
}
USERS_SQL = (
    "SELECT session_date, channel_group, device_category, user_pseudo_id "
    "FROM `{project}.{dataset}.int_sessions`"
)

REPORT_ID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
GCP_ID = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
DATASET_ID = re.compile(r"^[A-Za-z0-9_]{1,1024}$")


def template_id(value):
    """Accept a bare report ID or a full report URL."""
    match = re.search(r"reporting/([0-9a-f-]{36})", value)
    rid = match.group(1) if match else value.strip()
    if not REPORT_ID.match(rid):
        raise ValueError(f"not a Looker Studio report ID or URL: {value!r}")
    return rid


def bigquery_params(project, dataset, billing, with_users):
    if not GCP_ID.match(project):
        raise ValueError(f"not a valid GCP project ID: {project!r}")
    if not DATASET_ID.match(dataset):
        raise ValueError(f"not a valid BigQuery dataset ID: {dataset!r}")
    params = []
    for alias, table in TABLES.items():
        params += [
            (f"ds.{alias}.connector", "bigQuery"),
            (f"ds.{alias}.type", "TABLE"),
            (f"ds.{alias}.projectId", project),
            (f"ds.{alias}.datasetId", dataset),
            (f"ds.{alias}.tableId", table),
            (f"ds.{alias}.datasourceName", LABELS[alias]),
        ]
        if billing:
            params.append((f"ds.{alias}.billingProjectId", billing))
    if with_users:
        params += [
            ("ds.users.connector", "bigQuery"),
            ("ds.users.type", "CUSTOM_QUERY"),
            ("ds.users.projectId", project),
            ("ds.users.billingProjectId", billing or project),
            ("ds.users.sql", USERS_SQL.format(project=project, dataset=dataset)),
            ("ds.users.datasourceName", LABELS["users"]),
        ]
    return params


def sheets_params(spreadsheet, gids):
    missing = [a for a in TABLES if a not in gids]
    if missing:
        raise ValueError(f"--gid missing for: {', '.join(missing)}")
    params = []
    for alias in TABLES:
        params += [
            (f"ds.{alias}.connector", "googleSheets"),
            (f"ds.{alias}.spreadsheetId", spreadsheet),
            (f"ds.{alias}.worksheetId", gids[alias]),
            (f"ds.{alias}.hasHeader", "true"),
            (f"ds.{alias}.datasourceName", LABELS[alias]),
        ]
    return params


def build_url(args):
    params = [("c.reportId", template_id(args.template)), ("c.mode", args.mode)]
    if args.name:
        params.append(("r.reportName", args.name))
    if args.sheets:
        gids = dict(g.split("=", 1) for g in args.gid)
        params += sheets_params(args.sheets, gids)
    else:
        if not (args.project and args.dataset):
            raise ValueError("give --project and --dataset (BigQuery) or --sheets (Google Sheets)")
        params += bigquery_params(args.project, args.dataset, args.billing, not args.no_users)
    if args.explain:
        params.append(("c.explain", "true"))
    # quote_via=quote keeps spaces as %20 and encodes the SQL safely.
    return BASE + "?" + urlencode(params, quote_via=quote, safe="")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", help="JSON file with the same keys as the long options")
    ap.add_argument("--template", help="master template report ID or URL")
    ap.add_argument("--name", help="name for the client's copy")
    ap.add_argument("--project", help="client GCP project with the marts")
    ap.add_argument("--dataset", help="BigQuery dataset with the marts")
    ap.add_argument("--billing", help="project billed for queries (defaults to --project)")
    ap.add_argument("--no-users", action="store_true", help="skip the users custom-query source")
    ap.add_argument("--sheets", help="spreadsheet ID instead of BigQuery")
    ap.add_argument("--gid", action="append", default=[], help="alias=worksheetId, repeat for each tab")
    ap.add_argument("--mode", choices=["edit", "view"], default="edit")
    ap.add_argument("--explain", action="store_true", help="add Looker's debug button")
    args = ap.parse_args(argv)

    if args.config:
        with open(args.config) as f:
            cfg = json.load(f)
        for key, value in cfg.items():
            key = key.replace("-", "_")
            if getattr(args, key, None) in (None, [], False):
                setattr(args, key, value)
    if not args.template:
        ap.error("--template is required (or set it in --config)")

    try:
        url = build_url(args)
    except ValueError as err:
        ap.error(str(err))
    print(url)
    if len(url) > 8000:
        print(f"warning: URL is {len(url)} characters; some browsers cut very long URLs", file=sys.stderr)


if __name__ == "__main__":
    main()
