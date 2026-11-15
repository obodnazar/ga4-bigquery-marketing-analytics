-- Intermediate: one row per session.
-- Attribution rule: the first non-empty event-scoped source/medium in the session,
-- ignoring the site's own domains.
-- Sessions with none are treated as (direct)/(none). This is simpler than GA4's
-- last-non-direct-click model, so channel totals will not match the GA4 UI exactly.

-- No PARTITION BY on purpose: the BigQuery sandbox drops partitions older than 60 days,
-- and this sample is from 2020-21. On a client's live export, partition by date.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.int_sessions`
CLUSTER BY channel_group, device_category
AS
WITH sessions AS (
  SELECT
    session_key,
    ANY_VALUE(user_pseudo_id)                                        AS user_pseudo_id,
    -- event_date is in the property's time zone, as in GA4 reports.
    MIN(event_date)                                                  AS session_date,
    MIN(event_ts)                                                    AS session_start_ts,
    MAX(session_number)                                              AS session_number,

    -- The store's own domains are skipped: a self-referral is a tracking gap
    -- (missing cross-domain / unwanted-referral setup), not a traffic source.
    -- For a client, replace the regex with their own domains.
    ARRAY_AGG(
      IF(event_source IS NOT NULL
           AND NOT REGEXP_CONTAINS(event_source, r'googlemerchandisestore\.com'),
         STRUCT(event_source AS source, event_medium AS medium, event_campaign AS campaign),
         NULL)
      IGNORE NULLS ORDER BY event_ts LIMIT 1
    )[SAFE_OFFSET(0)]                                                AS src,

    ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL)
      IGNORE NULLS ORDER BY event_ts LIMIT 1)[SAFE_OFFSET(0)]        AS landing_page,

    ANY_VALUE(device_category)                                       AS device_category,
    ANY_VALUE(country)                                               AS country,

    MAX(IF(session_engaged = '1', 1, 0))                             AS is_engaged,
    SUM(IFNULL(engagement_time_msec, 0)) / 1000                      AS engagement_sec,
    COUNTIF(event_name = 'page_view')                                AS page_views,

    MAX(IF(event_name = 'view_item',         1, 0))                  AS reached_view_item,
    MAX(IF(event_name = 'add_to_cart',       1, 0))                  AS reached_add_to_cart,
    MAX(IF(event_name = 'begin_checkout',    1, 0))                  AS reached_begin_checkout,
    MAX(IF(event_name = 'add_shipping_info', 1, 0))                  AS reached_add_shipping_info,
    MAX(IF(event_name = 'add_payment_info',  1, 0))                  AS reached_add_payment_info,
    MAX(IF(event_name = 'purchase',          1, 0))                  AS reached_purchase,

    COUNTIF(event_name = 'purchase')                                 AS transactions,
    SUM(IF(event_name = 'purchase', IFNULL(purchase_revenue_usd, 0), 0)) AS revenue_usd
  FROM `{{project}}.{{dataset}}.stg_events`
  WHERE session_key IS NOT NULL
  GROUP BY session_key
),

labelled AS (
  SELECT
    * EXCEPT (src),
    COALESCE(src.source, '(direct)')   AS session_source,
    COALESCE(src.medium, '(none)')     AS session_medium,
    COALESCE(src.campaign, '(not set)') AS session_campaign
  FROM sessions
)

SELECT
  *,
  CASE
    -- The public sample replaces some values with these placeholders.
    WHEN session_source IN ('<Other>', '(data deleted)')
      OR session_medium IN ('<Other>', '(data deleted)')              THEN 'Unknown (obfuscated)'
    WHEN session_source = '(direct)'
      AND session_medium IN ('(none)', '(not set)')                   THEN 'Direct'
    WHEN session_medium = 'organic'                                   THEN 'Organic Search'
    WHEN REGEXP_CONTAINS(session_medium, r'^(cpc|ppc|paidsearch)$')   THEN 'Paid Search'
    WHEN REGEXP_CONTAINS(session_medium, r'^(display|cpm|banner)$')   THEN 'Display'
    WHEN REGEXP_CONTAINS(session_medium, r'e[-_ ]?mail')              THEN 'Email'
    WHEN session_medium = 'referral'                                  THEN 'Referral'
    ELSE 'Other'
  END                                                                 AS channel_group
FROM labelled;
