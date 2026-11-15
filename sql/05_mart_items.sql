-- Mart: product performance from the items array.

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.mart_items`
AS
SELECT
  i.item_name,
  i.item_category,
  COUNTIF(e.event_name = 'view_item')                                     AS item_views,
  COUNTIF(e.event_name = 'add_to_cart')                                   AS add_to_carts,
  SUM(IF(e.event_name = 'purchase', IFNULL(i.quantity, 0), 0))            AS units_purchased,
  ROUND(SUM(IF(e.event_name = 'purchase', IFNULL(i.item_revenue_in_usd, 0), 0)), 2) AS item_revenue_usd
FROM `{{project}}.{{dataset}}.stg_events` AS e,
  UNNEST(e.items) AS i
WHERE e.event_name IN ('view_item', 'add_to_cart', 'purchase')
GROUP BY i.item_name, i.item_category;
