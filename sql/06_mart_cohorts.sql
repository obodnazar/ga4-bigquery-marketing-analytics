-- Mart: weekly retention. Cohort = ISO week of the user's first session in the data.
-- Users whose first visit was before the export window are cohorted on their
-- first session inside it, so early cohorts are slightly inflated.

CREATE OR REPLACE TABLE `{{project}}.{{dataset}}.mart_cohorts`
AS
WITH user_weeks AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_TRUNC(session_date, ISOWEEK) AS activity_week
  FROM `{{project}}.{{dataset}}.int_sessions`
),
first_week AS (
  SELECT user_pseudo_id, MIN(activity_week) AS cohort_week
  FROM user_weeks
  GROUP BY user_pseudo_id
)
SELECT
  f.cohort_week,
  DATE_DIFF(u.activity_week, f.cohort_week, ISOWEEK) AS week_number,
  COUNT(DISTINCT u.user_pseudo_id)                AS active_users
FROM user_weeks AS u
JOIN first_week AS f USING (user_pseudo_id)
GROUP BY cohort_week, week_number;
