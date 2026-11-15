-- Mart: daily performance by channel and device. This is the table a dashboard reads.
-- `users` is a distinct count and is NOT additive across days or channels;
-- sum sessions, transactions and revenue, never users.

-- No PARTITION BY on purpose: the BigQuery sandbox drops partitions older than 60 days,
-- and this sample is from 2020-21. On a client's live export, partition by date.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.mart_daily_channel`
AS
SELECT
  session_date,
  channel_group,
  device_category,
  COUNT(*)                                   AS sessions,
  COUNT(DISTINCT user_pseudo_id)             AS users,
  COUNTIF(session_number = 1)                AS new_user_sessions,
  SUM(is_engaged)                            AS engaged_sessions,
  SUM(page_views)                            AS page_views,
  SUM(transactions)                          AS transactions,
  ROUND(SUM(revenue_usd), 2)                 AS revenue_usd
FROM `{{project}}.{{dataset}}.int_sessions`
GROUP BY session_date, channel_group, device_category;
