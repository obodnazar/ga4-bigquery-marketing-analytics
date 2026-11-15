# Looker Studio master template: spec

Build this once by hand (about an hour). Every client report is then a copy made by
`scripts/looker_link.py` in about a minute, pointed at that client's BigQuery marts.

It works because the pipeline in `sql/` gives every client the same table and field names.
Don't rename fields in the template: a copy can only rebind to tables with the same schema.

## 1. Data sources and aliases

Add these to the template (from the portfolio dataset or any client's dataset), then go to
**Resource → Manage added data sources** and set the **Alias** column exactly as below.
The generator addresses each source by this alias.

| Alias | Table (BigQuery) | Used for |
|---|---|---|
| `daily` | `mart_daily_channel` | filters, scorecards, trends, channel table |
| `funnel` | `mart_funnel` | checkout funnel |
| `items` | `mart_items` | top products |
| `dq` | `dq_checks` | data-quality page |
| `users` | custom query on `int_sessions` (below) | the Users scorecard |

`users` custom query (distinct users can't be summed from the daily table, so this source keeps one row per session):

```sql
SELECT session_date, channel_group, device_category, user_pseudo_id
FROM `PROJECT.DATASET.int_sessions`
```

Set every source to **owner's credentials** (Data credentials → Owner). Copies made through
the Linking API start on the credentials of whoever opens the link; switch them to Owner
again before sharing a client copy.

### Calculated fields

In `daily`:

| Name | Formula | Type |
|---|---|---|
| Engagement rate | `SUM(engaged_sessions) / SUM(sessions)` | Percent |
| Transactions per session | `SUM(transactions) / SUM(sessions)` | Percent |
| Avg order value | `SUM(revenue_usd) / SUM(transactions)` | Currency (USD) |

In `users`: **Users** = `COUNT_DISTINCT(user_pseudo_id)`, Number.

In `funnel`: **Purchase rate** = `SUM(purchase) / SUM(sessions)`, Percent.

In `dq`: **Failing share** = `SUM(failing) / SUM(total)`, Percent; **Status** =
`CASE WHEN SUM(failing) = 0 THEN "✓ Pass" WHEN SUM(failing) / SUM(total) < 0.01 THEN "! Minor" ELSE "!! Review" END`.

Calculated fields are carried into every copy automatically.

## 2. Theme (Theme and layout → Customize)

| Setting | Value |
|---|---|
| Canvas size | 1200 × 1180 (Overview), 1200 × 760 (Data quality) |
| Grid | 20 px, snap to grid on |
| Page background | `#F9F9F7` |
| Component background | `#FFFFFF`, border `#E1E0D9` 1 px, radius 12 |
| Font | Roboto. Titles 15 px semibold, body 12 px |
| Text: primary / secondary / muted | `#0B0B0B` / `#52514E` / `#898781` |
| Gridlines | `#E1E0D9`, 1 px, solid |
| Chart palette (in this order) | `#2A78D6` `#EB6834` `#1BAF7A` `#EDA100` `#E87BA4` `#008300` `#6250D6` `#E34948` |
| Status colours (DQ page only) | pass `#0CA30C`, minor `#FAB219`, review `#EC835A` |

The palette order is checked for colour-blind separation. Keep it, and in **Theme → Dimension
value colours** pin channels to fixed colours (Direct → slot 1, Organic Search → 2,
Unknown → 3, Paid Search → 4, Referral → 5, Other → 6, Email → 7), so a filter never
repaints a channel.

## 3. Page "Overview" (1200 × 1180)

```
y=0     ┌ Header: title · subtitle · data-freshness text ─────────────────────────────┐
y=100   │ [Date range]   [Device ▾]   [Channel ▾]                                      │
y=160   │ Sessions │ Users │ Engagement │ Transactions │ Revenue │ Tx/session │ AOV    │
y=280   │ Daily sessions (time series)        │ Daily revenue (time series)            │
y=600   │ Channels (table, full width)                                                 │
y=900   │ Checkout funnel (bar)                │ Top products (bar)                    │
y=1180  └──────────────────────────────────────────────────────────────────────────────┘
```

| # | Component | x, y, w, h | Source | Setup |
|---|---|---|---|---|
| 1 | Text: title | 40, 24, 800, 36 | n/a | "GA4 e-commerce performance", 24 px semibold |
| 2 | Text: subtitle | 40, 62, 800, 24 | n/a | client name · source · period, 13 px secondary |
| 3 | Date range control | 40, 100, 260, 40 | `daily` | default: Last 90 days (portfolio: custom 1 Nov 2020 – 31 Jan 2021) |
| 4 | Drop-down | 320, 100, 220, 40 | `daily` | `device_category` |
| 5 | Drop-down | 560, 100, 220, 40 | `daily` | `channel_group` |
| 6–12 | Scorecards, 7 in a row | x = 40 + i × 160, y 160, w 150, h 100 | `daily` (Users: `users`) | Sessions, Users, Engagement rate, Transactions, revenue_usd, Transactions per session, Avg order value. Compact numbers, comparison off |
| 13 | Time series | 40, 280, 550, 300 | `daily` | dim `session_date` (day), metric `sessions`, line 2 px, no points |
| 14 | Time series | 610, 280, 550, 300 | `daily` | dim `session_date`, metric `revenue_usd` |
| 15 | Table with bars | 40, 600, 1120, 280 | `daily` | dim `channel_group` (drill-down `device_category`); metrics sessions (bar), Engagement rate, transactions, Transactions per session, revenue_usd; sort sessions desc; rows 10 |
| 16 | Bar chart (horizontal) | 40, 900, 550, 260 | `funnel` | metrics in this order: sessions, view_item, add_to_cart, begin_checkout, add_shipping_info, add_payment_info, purchase; no dimension; single colour slot 1; data labels on |
| 17 | Bar chart (horizontal) | 610, 900, 550, 260 | `items` | dim `item_name`, metric `item_revenue_usd`, sort desc, top 10, slot 1 |

Filter wiring:
- The `users` source must use the same filter fields. Put components 3–5 and the Users
  scorecard in one group, or check that the date control applies to `session_date` in `users` too.
- The funnel and items sources have no date field. Put a muted 11 px note under each: "All dates".

## 4. Page "Data quality" (1200 × 760)

| # | Component | x, y, w, h | Source | Setup |
|---|---|---|---|---|
| 1 | Text | 40, 24, 1120, 60 | n/a | "Checks run on the raw export before building the marts." |
| 2 | Table | 40, 100, 1120, 380 | `dq` | dims `check_order`, `check_name`, Status; metrics failing, total, Failing share; sort check_order asc; conditional formatting on Status: pass / minor / review colours as **text colour with the symbol**, never colour alone |
| 3 | Text | 40, 500, 1120, 220 | n/a | 3–5 bullet findings written for this client (copy from the audit) |

## 5. UX rules this template follows

- Answer first: scorecards before trends, trends before detail.
- One metric per chart, never a second axis.
- Filters in one row at the top; the same controls on every page (Report-level components).
- Distinct users only from the `users` source, never summed.
- Colour encodes identity (channel) or status, never decoration. Status always comes with a symbol and text.
- Labels in plain words ("Transactions per session", not `tx_ps`).
- Mobile: check View → Mobile layout before sharing; stack scorecards 2 per row.

## 6. Per-client checklist (after the generator)

1. Open the generated link while signed in to the account that will own the copy.
2. Check every component renders (an error means a field name differs: fix the client's mart, not the template).
3. Data credentials → Owner for every source.
4. Change subtitle and the findings text on the Data quality page.
5. Totals check against BigQuery: `SELECT SUM(sessions), SUM(transactions), SUM(revenue_usd) FROM mart_daily_channel`.
6. Share → client's email as Viewer, or transfer ownership.
