-- Staging: one row per GA4 event, with the event_params we need pulled into columns.
-- Source: Google's public, obfuscated GA4 export of the Google Merchandise Store.
-- Nothing downstream reads the raw export directly; if a field is wrong, fix it here.

-- No PARTITION BY on purpose: the BigQuery sandbox drops partitions older than 60 days,
-- and this sample is from 2020-21. On a client's live export, partition by date.
CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.stg_events`
CLUSTER BY event_name, user_pseudo_id
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date)                                   AS event_date,
  TIMESTAMP_MICROS(event_timestamp)                                  AS event_ts,
  event_name,
  user_pseudo_id,

  -- GA4 has no session table. A session is user_pseudo_id + ga_session_id.
  -- CONCAT returns NULL when ga_session_id is missing, so those events
  -- drop out of sessions and are counted in the data-quality checks instead.
  CONCAT(
    user_pseudo_id, '.',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )                                                                  AS session_key,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number')    AS session_number,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')        AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title')           AS page_title,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  -- session_engaged arrives as a string in some rows and an int in others.
  (SELECT COALESCE(value.string_value, CAST(value.int_value AS STRING))
     FROM UNNEST(event_params) WHERE key = 'session_engaged')                              AS session_engaged,

  -- Event-scoped traffic source (what GA4 uses for session attribution).
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')   AS event_source,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')   AS event_medium,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS event_campaign,

  -- User-scoped first touch. Kept for comparison, never mixed with session source.
  traffic_source.source                                              AS first_user_source,
  traffic_source.medium                                              AS first_user_medium,

  device.category                                                    AS device_category,
  device.operating_system                                            AS operating_system,
  geo.country                                                        AS country,

  ecommerce.transaction_id                                           AS transaction_id,
  ecommerce.purchase_revenue_in_usd                                  AS purchase_revenue_usd,
  ecommerce.total_item_quantity                                      AS total_item_quantity,
  items
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '{{start}}' AND '{{end}}';
