-- Mart: e-commerce funnel by device and channel.
-- Open funnel: a session counts at a step if it fired that event at all,
-- in any order. A strict ordered funnel would give lower numbers.

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.mart_funnel`
AS
SELECT
  device_category,
  channel_group,
  COUNT(*)                         AS sessions,
  SUM(reached_view_item)           AS view_item,
  SUM(reached_add_to_cart)         AS add_to_cart,
  SUM(reached_begin_checkout)      AS begin_checkout,
  SUM(reached_add_shipping_info)   AS add_shipping_info,
  SUM(reached_add_payment_info)    AS add_payment_info,
  SUM(reached_purchase)            AS purchase
FROM `{{project}}.{{dataset}}.int_sessions`
GROUP BY device_category, channel_group;
