# GA4 → BigQuery marketing analytics

A small, complete version of what I build for marketing teams: GA4 raw events turned into
trusted, dashboard-ready tables in BigQuery, with data-quality checks before any number
reaches a chart.

It runs on Google's **public, obfuscated GA4 export of the Google Merchandise Store**
(`bigquery-public-data.ga4_obfuscated_sample_ecommerce`, Nov 2020 – Jan 2021), so anyone
can reproduce it. No client data is used.

**Live dashboard:** https://obodnazar.github.io/ga4-bigquery-marketing-analytics/

## The problem it solves

GA4's interface is fine for quick looks, but teams hit the same walls:

- the numbers in GA4, the ad platforms and the CRM don't agree, and nobody knows which one is right;
- sessions, channels and funnels have to be rebuilt from raw events in BigQuery, and it is easy to get them subtly wrong;
- dashboards get built straight on raw tables, so one tracking bug quietly breaks every report.

## What's inside

```
sql/
  01_stg_events.sql         raw export → one clean row per event, params pulled into columns
  02_int_sessions.sql       events → one row per session: source/medium, channel, landing page, funnel flags, revenue
  03_mart_daily_channel.sql day × channel × device: sessions, users, engagement, transactions, revenue
  04_mart_funnel.sql        checkout funnel by device and channel
  05_mart_items.sql         product views, add-to-carts, units, revenue
  06_mart_cohorts.sql       weekly retention cohorts
  90_dq_checks.sql          nine data-quality checks on the raw export
scripts/
  run_pipeline.py           builds every table, exports the marts, rebuilds the dashboard
  build_dashboard.py        embeds the exported CSVs into a static HTML dashboard
  looker_link.py            Linking API URL: copies the Looker master template onto a client's marts
dashboard/                  the dashboard (template + built page)
docs/looker-studio.md       how the Sheets-based Looker Studio version is wired
docs/looker-template-spec.md  the Looker master template: aliases, fields, theme, exact layout
```

Layers follow one rule: **raw is never edited, every table is derived by SQL from the layer
below, and dashboards read only marts.** If a number is wrong you fix the model, not the chart.

## Decisions worth explaining

| Decision | Why |
|---|---|
| Session key = `user_pseudo_id` + `ga_session_id` | GA4 has no session table; this is the standard way to rebuild one. Events with no session ID are counted in the checks instead of silently dropped. |
| Session source = first event-scoped source/medium in the session | Uses the session's own traffic data, not `traffic_source.*`, which is the user's *first* touch and is a common source of wrong channel reports. |
| Users exported pre-aggregated for every filter combination | Distinct users are not additive across days or channels. Summing them is the most common dashboard error I see. |
| Open funnel | A session counts at a step if it fired that event at all. Simpler to explain to stakeholders; the SQL notes say how to make it strict. |
| Clustered by event / channel; no date partitions here | On a live export I partition by date. In the BigQuery sandbox, partitions older than 60 days are deleted on creation, and this sample is from 2020–21, so the first run produced an empty table. Clustering keeps queries cheap without that risk. |
| `maximum_bytes_billed` on every query | A runaway query fails instead of costing money. |

## Data-quality checks

Before trusting any client's GA4 export I check:

1. events with no `ga_session_id` (cannot be sessionised);
2. `page_view` events with no `page_location`;
3. purchases with a missing or `(not set)` `transaction_id`;
4. transaction IDs recorded more than once (double-counted revenue);
5. purchases where order revenue ≠ sum of item revenue;
6. purchases with zero or missing revenue;
7. events whose source is the site's own domain (self-referral);
8. sessions whose source is hidden;
9. items with no name.

Results for this dataset are in the dashboard's last section.

## Findings on this dataset

92 days, 4,295,584 events, 360,129 sessions, 270,154 users, 5,692 purchases, $362,165 revenue.
Mart totals reconcile exactly with the raw export.

**What I would tell this client, in priority order:**

1. **Up to 6% of revenue may be double-counted.** 326 transaction IDs are recorded more than once (335 extra purchase events, up to $22,148). 311 of them repeat inside the same session with a median gap of 0 minutes, which points to the purchase tag firing twice or the thank-you page being reloaded. Fix: fire `purchase` once per order; until then, deduplicate by `transaction_id` in reporting.
2. **Revenue tracking broke at the end of January.** 450 purchases (7.9%) carry $0 revenue, and from 27 January it is 199 of 227 (88%). The revenue drop in the trend chart after that date is a tracking failure, not a sales drop.
3. **One in six purchases can't be reconciled with orders.** 906 purchases (15.9%, $31,817) have no `transaction_id`, so they can't be deduplicated or matched to the shop's back end.
4. **The site refers traffic to itself.** 53% of events that carry a source point to the store's own domain, and 31% of sessions contain such an event. For 55,859 sessions (15.5%) it is the only source, so a standard report would credit them to "Referral" from the shop itself. Fix: cross-domain measurement and the unwanted-referrals list in GA4. The models here skip the shop's own domains when attributing.
5. **One checkout step tells you nothing.** In 85% of sessions (9,492 of 11,104) `add_shipping_info` fires within one second of `begin_checkout` (median gap 0 ms), so the two steps are effectively the same event and the funnel can't show where people drop off.
6. **Channel data changes overnight on 22 January.** Paid Search falls from 60–100 sessions a day to 5 or fewer, obfuscated sources drop by more than half, and Referral jumps. Traffic didn't change that fast; something in tagging or attribution did. Explain this before anyone reads the January channel trend.
7. **Product reports split the same product.** For example, *Google Crewneck Sweatshirt Navy* sits under both *Apparel* ($4,356) and *Uncategorized Items* ($6,204). Several top sellers have purchases but no `view_item` events (e.g., *Google F/C Longsleeve Charcoal*: 180 units sold, 0 views), so product-view tracking is incomplete.
8. **"Revenue" needs one definition.** In 1,001 purchases (17.6%) order revenue differs from the sum of item revenue: higher in 519 (likely shipping or tax), lower in 482 (likely discounts). The business has to pick which number is "revenue" before comparing it with finance.

**Once the data is fixed, the first business questions** the marts already answer (read with the caveats above):

- Organic Search converts about twice as well as Direct (2.0% vs 1.0% transactions per session); Paid Search is the lowest at 0.7%, worth checking against ad spend.
- Mobile and desktop convert almost the same (1.4% vs 1.3% of sessions with a purchase), so mobile UX is not the obvious bottleneck.
- November cohorts come back in week 1 at 5–7%, December cohorts at 2.5–3.3%: holiday shoppers return about half as often.

The marts keep the raw numbers (no deduplication) so they reconcile with GA4. Deduplicating is a decision to agree with the client, not something to do silently.

## Run it yourself

1. Create a free Google Cloud project with the BigQuery sandbox (no card needed; 1 TB of queries per month free).
2. Install the Google Cloud SDK and log in: `gcloud auth login`.
3. Run:

```bash
python3 scripts/run_pipeline.py --project YOUR_PROJECT_ID
```

It creates the `ga4_portfolio` dataset in the US (where the public data lives), builds every
table, exports the marts to `data/` and writes `dashboard/index.html`.
In the sandbox, tables expire after 60 days (just run it again), and `INSERT`/`UPDATE` are not allowed, which is why every model is a `CREATE OR REPLACE TABLE`.

## Known limits

- The public sample is obfuscated: some sources, IDs and values are replaced with `<Other>` or `(data deleted)`. The checks show how much.
- Channel attribution is simpler than GA4's last-non-direct model, so channel totals will not match the GA4 interface exactly.
- Cohorts start at the first session *inside* the export window, so early cohorts are slightly inflated.

---

Nazar Obod · analytics engineer (GA4, GTM, BigQuery, Looker Studio) · [LinkedIn](https://www.linkedin.com/in/nazar-obod/)
