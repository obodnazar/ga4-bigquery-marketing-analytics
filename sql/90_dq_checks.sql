-- Data-quality checks. Each row: what was checked, how many rows fail, out of how many.
-- These are the checks I run before trusting any GA4 export a client hands over.

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.dq_checks`
AS
WITH purchases AS (
  SELECT
    transaction_id,
    purchase_revenue_usd,
    (SELECT SUM(IFNULL(item_revenue_in_usd, 0)) FROM UNNEST(items)) AS items_revenue_usd
  FROM `{{project}}.{{dataset}}.stg_events`
  WHERE event_name = 'purchase'
),
real_ids AS (
  SELECT transaction_id, COUNT(*) AS n
  FROM purchases
  WHERE transaction_id IS NOT NULL AND transaction_id != '(not set)'
  GROUP BY transaction_id
)

SELECT 1 AS check_order,
  'Events without ga_session_id (cannot be sessionised)' AS check_name,
  COUNTIF(session_key IS NULL) AS failing, COUNT(*) AS total
FROM `{{project}}.{{dataset}}.stg_events`

UNION ALL
SELECT 2, 'page_view events without page_location',
  COUNTIF(page_location IS NULL), COUNT(*)
FROM `{{project}}.{{dataset}}.stg_events`
WHERE event_name = 'page_view'

UNION ALL
SELECT 3, 'Purchases with missing or (not set) transaction_id',
  COUNTIF(transaction_id IS NULL OR transaction_id = '(not set)'), COUNT(*)
FROM purchases

UNION ALL
SELECT 4, 'Transaction IDs recorded more than once (possible double-counted revenue)',
  COUNTIF(n > 1), COUNT(*)
FROM real_ids

UNION ALL
SELECT 5, 'Purchases where order revenue differs from the sum of item revenue by > $0.01',
  COUNTIF(ABS(IFNULL(purchase_revenue_usd, 0) - IFNULL(items_revenue_usd, 0)) > 0.01), COUNT(*)
FROM purchases

UNION ALL
SELECT 6, 'Purchases with zero or missing revenue',
  COUNTIF(IFNULL(purchase_revenue_usd, 0) = 0), COUNT(*)
FROM purchases

UNION ALL
SELECT 7, "Events whose source is the site's own domain (self-referral: cross-domain not set up)",
  COUNTIF(REGEXP_CONTAINS(event_source, r'googlemerchandisestore\.com')), COUNTIF(event_source IS NOT NULL)
FROM `{{project}}.{{dataset}}.stg_events`

UNION ALL
SELECT 8, 'Sessions whose source is hidden by obfuscation (<Other> / (data deleted))',
  COUNTIF(channel_group = 'Unknown (obfuscated)'), COUNT(*)
FROM `{{project}}.{{dataset}}.int_sessions`

UNION ALL
SELECT 9, 'Item rows with item_name (not set)',
  COUNTIF(i.item_name IS NULL OR i.item_name = '(not set)'), COUNT(*)
FROM `{{project}}.{{dataset}}.stg_events`, UNNEST(items) AS i;
