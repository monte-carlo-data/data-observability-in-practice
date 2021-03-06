.headers on

WITH NULL_RATES AS(
  SELECT
    DATE_ADDED,
    CAST(
      SUM(
        CASE
          WHEN AVG_TEMP IS NULL THEN 1
          ELSE 0
        END
      ) AS FLOAT
    ) / COUNT(*) AS AVG_TEMP_NULL_RATE
  FROM
    EXOPLANETS
  GROUP BY
    DATE_ADDED
),

ALL_DATES AS (
  SELECT
    *,
    JULIANDAY(DATE_ADDED) - JULIANDAY(LAG(DATE_ADDED)
      OVER(
        ORDER BY DATE_ADDED
      )
    ) AS DAYS_SINCE_LAST_ALERT
  FROM
    NULL_RATES
  WHERE
    AVG_TEMP_NULL_RATE > 0.9
)

SELECT
  DATE_ADDED,
  AVG_TEMP_NULL_RATE
FROM
  ALL_DATES
WHERE
  DAYS_SINCE_LAST_ALERT IS NULL OR DAYS_SINCE_LAST_ALERT > 1;
