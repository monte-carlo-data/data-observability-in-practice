.headers on

SELECT
  DATE_ADDED,
  COUNT(*) AS ROWS_ADDED
FROM
  EXOPLANETS
GROUP BY
  DATE_ADDED;