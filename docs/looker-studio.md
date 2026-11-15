# Putting the marts into Looker Studio

Most clients want the dashboard in Looker Studio, not HTML. The marts are built for it:
Looker reads one small, pre-aggregated table per chart instead of the raw export.
Takes about 20 minutes by hand.

## 1. Data sources

In Looker Studio: **Create → Data source → BigQuery → your project → `ga4_portfolio`**.
Add three sources:

| Source | Table | Date field |
|---|---|---|
| Daily channel | `mart_daily_channel` | `session_date` |
| Funnel | `mart_funnel` | none |
| Items | `mart_items` | none |

In **Daily channel**, add calculated fields (do not use the `users` column in totals; it is not additive):

| Field | Formula |
|---|---|
| Engagement rate | `SUM(engaged_sessions) / SUM(sessions)` |
| Transactions per session | `SUM(transactions) / SUM(sessions)` |
| Avg order value | `SUM(revenue_usd) / SUM(transactions)` |

For an accurate Users scorecard, add a fourth source as a **custom query**:

```sql
SELECT session_date, channel_group, device_category, user_pseudo_id
FROM `YOUR_PROJECT.ga4_portfolio.int_sessions`
```

and use `COUNT_DISTINCT(user_pseudo_id)`.

## 2. Page layout

1. Controls row: date range, `device_category`, `channel_group`.
2. Scorecards: sessions, users (custom query source), engagement rate, transactions, revenue, transactions per session, AOV.
3. Two time series: sessions by `session_date`; revenue by `session_date`. One metric per chart, no second axis.
4. Table: `channel_group` with sessions, engagement rate, transactions, transactions per session, revenue; bar-in-cell on sessions.
5. Bar chart from **Funnel**: the step columns as metrics, filtered by the same controls.
6. Bar chart from **Items**: top 10 `item_name` by `item_revenue_usd`.

## 3. Before sharing

- Set every chart's data source to the mart, never to `stg_events`.
- Check the scorecard totals against the `data/*.csv` exports from the pipeline.
- Share as "Viewer" and paste the link into the README.
