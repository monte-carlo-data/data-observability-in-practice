.headers on

SELECT
  DATE_ADDED,
  CAST(
    SUM(
      CASE
        WHEN DISTANCE IS NULL THEN 1
        ELSE 0
      END
    ) AS FLOAT) / COUNT(*) AS DISTANCE_NULL_RATE,
  CAST(
    SUM(
      CASE
        WHEN G IS NULL THEN 1
        ELSE 0
      END
    ) AS FLOAT) / COUNT(*) AS G_NULL_RATE,
  CAST(
    SUM(
      CASE
        WHEN ORBITAL_PERIOD IS NULL THEN 1
        ELSE 0
      END
    ) AS FLOAT) / COUNT(*) AS ORBITAL_PERIOD_NULL_RATE,
  CAST(
    SUM(
      CASE
        WHEN AVG_TEMP IS NULL THEN 1
        ELSE 0
      END
    ) AS FLOAT) / COUNT(*) AS AVG_TEMP_NULL_RATE
FROM
  EXOPLANETS
GROUP BY
  DATE_ADDED;