# Looker Studio version

Report: https://lookerstudio.google.com/reporting/b0e3799f-d253-4a1a-9642-75b9142ce666

## How the data gets there

`data/*.csv` in this repo → a Google Sheet that pulls each file with
`=IMPORTDATA("https://raw.githubusercontent.com/obodnazar/ga4-bigquery-marketing-analytics/main/data/<file>.csv"; ","; "en_US")`
(one tab per file; column A of the daily tab formatted as Date) → Looker Studio Google Sheets connector.

Nothing expires: the CSVs live in the repo, so the report keeps working after the BigQuery sandbox tables are gone.
Re-running the pipeline and pushing new CSVs updates the report.

## Already done

- Data source **Daily channel** (daily tab), **owner's credentials** so anyone with the link can view.
- Calculated fields in the data source:

| Field | Formula |
|---|---|
| Engagement rate | `SUM(engaged_sessions) / SUM(sessions)` |
| Transactions per session | `SUM(transactions) / SUM(sessions)` |
| Avg order value | `SUM(revenue_usd) / SUM(transactions)` |

- Channel table: dimension `channel_group` (drill-down to `device_category`), metrics sessions, transactions, Engagement rate, Transactions per session, revenue_usd.

## Finishing the layout (about 15 minutes, full screen)

1. **Title.** Double-click "Daily channel" → `GA4 e-commerce performance · Google Merchandise Store (public sample)`.
2. **Channel table.** Drag it to the bottom and stretch it to full width. In *Style*, set Engagement rate and Transactions per session to *Percent* (or set the field type to Percent in the data source).
3. **Controls row.** *Add a control* → Date range control; then Drop-down list with `device_category`; then another with `channel_group`. Put them in one row at the top. Set the date range default to *Custom: 1 Nov 2020 – 31 Jan 2021*.
4. **Scorecards row.** *Add a chart* → Scorecard, six times: sessions, transactions, revenue_usd, Engagement rate, Transactions per session, Avg order value. Use compact numbers.
5. **Trends.** *Add a chart* → Time series, twice: `session_date` × sessions, and `session_date` × revenue_usd. One metric per chart, no second axis.
6. **Users.** Don't add a Users scorecard from this table: distinct users can't be summed across days. The HTML dashboard has correct pre-aggregated users.
7. **Optional second page** "Data quality": *Add data* → Google Sheets → the same spreadsheet, checks tab → a table with check_name, failing, total and a calculated `failing / total` as Percent.
8. **Check the totals** with the date filter set to the full period: sessions 360,129 · transactions 5,692 · revenue $362,165.
9. **Share.** *Share* → *Manage access* → "Anyone with the link can view". Paste the link into the README.
