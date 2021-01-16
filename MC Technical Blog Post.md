# Data Observability in Practice Using SQLite3
## A Look Under the Hood
___
## Data Observability, Conceptually

In the past, we've defined **data downtime** as "periods of time where data is missing, erroneous, or otherwise inaccurate." Data downtime prompts us to ask questions such as:
- Is the data up-to-date?
- Is the data complete?
- Are fields within expected ranges?
- Is the null rate higher or lower than it should be?
- Has the schema changed?

We call an organization's ability to answer these questions and assess the health of their data ecosystem as **data observability**. Previously, we've delinated five key pillars of data observability:
- **Freshness**: is my data up to date? Are there gaps in time where my data has not been updated?
- **Distribution**: how healthy is my data at the field-level? Are my data within expected ranges?
- **Volume**: is my data intake meeting expected thresholds?
- **Schema**: has the formal structure of my data management system changed?
- **Lineage**: if some of my data is down, what is affected upstream and downstream? How do my data sources depend on one another?

It's one thing to talk about data observability in this conceptual way, but a complete treatment should pull back the curtain -- what does data observability *actually* look like, under the hood, in the code?

In this article I devised a tiny example data ecosystem, in an attempt to explore what data observability looks like in practice. The data itself as well as code snippets are available on Github here (==TODO==). Let's take a look.
___

## Data Observability in Practice
Our sample data ecosystem uses mock astronomical data about habitable exoplanets. I'm using `sqlite3.32.3` to interface with it.
```
$ sqlite3 EXOPLANETS.db
sqlite> PRAGMA TABLE_INFO(EXOPLANETS);
0 | _id            | TEXT | 0 | | 0
1 | distance       | REAL | 0 | | 0
2 | g              | REAL | 0 | | 0
3 | orbital_period | REAL | 0 | | 0
4 | avg_temp       | REAL | 0 | | 0
5 | date_added     | TEXT | 0 | | 0
```

A database entry in `EXOPLANETS` contains the following info:

0. `_id`: A UUID corresponding to the planet.
1. `distance`: Distance from Earth, in lightyears.
2. `g`: Surface gravity as a multiple of $g$, the gravitational force constant.
3. `orbital_period`: Length of a single orbital cycle in days.
4. `avg_temp`: Average surface temperature in degrees Kelvin.
5. `date_added`: The date our system discovered the planet and added it automatically to our databases.

Note that one or more of `distance`, `g`, `orbital_period`, and `avg_temp` may be `NULL` for a given planet as a result of missing or erroneous data.

```
sqlite> SELECT * FROM EXOPLANETS LIMIT 5;
c168b188-ef0c-4d6a-8cb2-f473d4154bdb|34.6273036348341||476.480044083599||2020-01-01
e7b56e84-41f4-4e62-b078-01b076cea369|110.196919810563|2.52507362359066|839.8378167897||2020-01-01
a27030a0-e4b4-4bd7-8d24-5435ed86b395|26.6957950454452|10.2764970016067|301.018816321399||2020-01-01
54f9cf85-eae9-4f29-b665-855357a14375|54.8883521129783||173.788967912197|328.644125249613|2020-01-01
4d06ec88-f5c8-4d03-91ef-7493a12cd89e|153.264217159834|0.922874568459221|200.712661803056||2020-01-01
```

It's worthwhile to note that this exercise is *retroactive* -- we're looking at data that has already been entered in the past. In a real production application, data observability is real time, and will thus involve a slightly different implementation than what is done here.

## Freshness
First, note the `DATE_ADDED` column. SQL doesn't store metadata on when individual records are added. So, to visualize freshness in this retroactive setting, we need to track that info ourselves.

Grouping by the `DATE_ADDED` column can give us insight into how `EXOPLANETS` updates daily. For example, we can query for the number of new IDs added per day:
```
sqlite> SELECT
   ...>     DATE_ADDED,
   ...>     COUNT(*) AS ROWS_ADDED
   ...> FROM
   ...>     EXOPLANETS
   ...> GROUP BY
   ...>     DATE_ADDED;
2020-01-01 | 84
2020-01-02 | 92
2020-01-03 | 101
2020-01-04 | 102
2020-01-05 | 100
...
2020-07-14 | 104
2020-07-15 | 110
2020-07-16 | 103
2020-07-17 | 89
2020-07-18 | 104
```

It looks like `EXOPLANETS` consistently updates with around 100 new entries each day, though there are gaps where no data comes in for multiple days. Recall that with freshness, we want to ask the question "is my data up to date?" -- thus, knowing about those gaps in table updates is essential.

This query operationalizes freshness by introducing a metric for `DAYS_SINCE_LAST_UPDATE`:
```
sqlite> WITH UPDATES AS(
   ...>     SELECT
   ...>         DATE_ADDED,
   ...>         COUNT(*) AS ROWS_ADDED
   ...>     FROM
   ...>         EXOPLANETS
   ...>     GROUP BY
   ...>         DATE_ADDED
   ...> )
   ...> SELECT
   ...>     DATE_ADDED,
   ...>     JULIANDAY(DATE_ADDED) - JULIANDAY(LAG(DATE_ADDED) OVER(ORDER BY DATE_ADDED)) AS DAYS_SINCE_LAST_UPDATE
   ...> FROM
   ...>     UPDATES;
2020-01-01 |
2020-01-02 | 1.0
2020-01-03 | 1.0
2020-01-04 | 1.0
2020-01-05 | 1.0
...
2020-07-14 | 1.0
2020-07-15 | 1.0
2020-07-16 | 1.0
2020-07-17 | 1.0
2020-07-18 | 1.0
```

The resulting table says "on date *X*, the most recent data in `EXOPLANETS` was *Y* years old". This is info not explicitly available from the `DATE_ADDED` column in the table -- we needed to uncover it.

A small modification to this code turns the query into a *freshness detector*:
```
sqlite> WITH UPDATES AS(
   ...>     SELECT
   ...>         DATE_ADDED,
   ...>         COUNT(*) AS ROWS_ADDED
   ...>     FROM
   ...>         EXOPLANETS
   ...>     GROUP BY
   ...>         DATE_ADDED
   ...> ),
   ...> NUM_DAYS_UPDATES AS (SELECT
   ...>     DATE_ADDED,
   ...>     JULIANDAY(DATE_ADDED) - JULIANDAY(LAG(DATE_ADDED) OVER(ORDER BY DATE_ADDED)) AS DAYS_SINCE_LAST_UPDATE
   ...> FROM
   ...>     UPDATES
   ...> )
   ...> SELECT
   ...>     *
   ...> FROM
   ...>     NUM_DAYS_UPDATES
   ...> WHERE
   ...>     DAYS_SINCE_LAST_UPDATE > 1;
2020-02-08 | 8.0
2020-03-30 | 4.0
2020-05-14 | 8.0
2020-06-07 | 3.0
2020-06-17 | 5.0
2020-06-30 | 3.0
```

Now, the data returned represents dates where *freshness incidents* occurred. On 2020-05-14, the most recent data in the table was 8 days old! Such an outage may represent a fault in our data pipeline or measuring instruments, and would be good to know about if we're using this data for anything worthwhile.

Note in particular the last line of the query: `DAYS_SINCE_LAST_UPDATE > 1;`. Here, `1` is a **hyperparameter** -- there's nothing "correct" about this number, though changing it will impact what dates we consider to be incidents. We could change `1` to `7` and thus only catch the two worst outages on 2020-02-08 and 2020-05-14. Any choice here will reflect the particular use case and objectives, and is an important balance to strike that comes up again and again in data observability.

## Distribution
Next, we want to assess the field-level, distributional health of our data. One of the simplest questions is, "how often is my data `NULL`"? In many cases some level of incomplete data is acceptable -- but if a 10% null rate turns into 90%, we'll want to know.
```
sqlite> SELECT
   ...>     DATE_ADDED,
   ...>     CAST(SUM(CASE WHEN DISTANCE IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS DISTANCE_NULL_RATE,
   ...>     CAST(SUM(CASE WHEN G IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS G_NULL_RATE,
   ...>     CAST(SUM(CASE WHEN ORBITAL_PERIOD IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS ORBITAL_PERIOD_NULL_RATE,
   ...>     CAST(SUM(CASE WHEN AVG_TEMP IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS AVG_TEMP_NULL_RATE    
   ...> FROM
   ...>     EXOPLANETS
   ...> GROUP BY
   ...>     DATE_ADDED;
2020-01-01|0.0833333333333333|0.178571428571429|0.214285714285714|0.380952380952381
2020-01-02|0.0|0.152173913043478|0.326086956521739|0.402173913043478
2020-01-03|0.0594059405940594|0.188118811881188|0.237623762376238|0.336633663366337
2020-01-04|0.0490196078431373|0.117647058823529|0.264705882352941|0.490196078431373
2020-01-05|0.04|0.18|0.28|0.3
```

This query returns a lot of data! What's going on?

The general formula `CAST(SUM(CASE WHEN SOME_METRIC IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)`, when grouped by the `DATE_ADDED` column, is telling us the rate of `NULL` values for `SOME_METRIC` in the daily batches of new data in `EXOPLANETS`. It's hard to get a sense by looking at the raw output, but a visual can help illuminate:
==TODO python plots of the null rate plots==

The visuals make it clear that there are null rate "spike" events we should be detecting. Let's focus on just the last metric, `AVG_TEMP`, for now. We can detect null spikes most simply with a naive threshold:
```
sqlite> WITH NULL_RATES AS(
   ...>     SELECT
   ...>         DATE_ADDED,
   ...>         CAST(SUM(CASE WHEN AVG_TEMP IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS AVG_TEMP_NULL_RATE    
   ...>     FROM
   ...>         EXOPLANETS
   ...>     GROUP BY
   ...>         DATE_ADDED
   ...> )
   ...> SELECT
   ...>     *
   ...> FROM
   ...>     NULL_RATES
   ...> WHERE
   ...>     AVG_TEMP_NULL_RATE > 0.9;
2020-03-09 | 0.967391304347826
2020-06-02 | 0.929411764705882
2020-06-03 | 0.977011494252874
2020-06-04 | 0.989690721649485
2020-06-07 | 0.987804878048781
2020-06-08 | 0.961904761904762
```

This is fine, but 2020-06-02 through 2020-06-04 seem like the same incident. We can filter out dates that occur immediately after other alerts:

```
WITH NULL_RATES AS(
  SELECT
    DATE_ADDED,
    CAST(SUM(CASE WHEN AVG_TEMP IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS AVG_TEMP_NULL_RATE
  FROM
    EXOPLANETS
  GROUP BY
    DATE_ADDED
),

ALL_DATES AS (
  SELECT
    *,
    JULIANDAY(DATE_ADDED) - JULIANDAY(LAG(DATE_ADDED) OVER(ORDER BY DATE_ADDED)) AS DAYS_SINCE_LAST_ALERT
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
___
$ sqlite3 EXOPLANETS.db < dist-query-only-start-dates.sql
2020-03-09|0.967391304347826
2020-06-02|0.929411764705882
2020-06-07|0.987804878048781
```

Note that in both of these queries, the key hyperparameter is `0.9`, which we use as a naive null rate threshold. We can be a bit more intelligent, and use the concept of **rolling average** with a more intelligent hyperparameter:

```
WITH NULL_RATES AS(
  SELECT
    DATE_ADDED,
    CAST(SUM(CASE WHEN AVG_TEMP IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS AVG_TEMP_NULL_RATE
  FROM
    EXOPLANETS
  GROUP BY
    DATE_ADDED
),

NULL_WITH_AVG AS(
  SELECT
    *,
    AVG(AVG_TEMP_NULL_RATE) OVER (
      ORDER BY DATE_ADDED ASC
      ROWS BETWEEN 14 PRECEDING AND CURRENT ROW) AS TWO_WEEK_ROLLING_AVG
  FROM
    NULL_RATES
  GROUP BY
    DATE_ADDED
)

SELECT
  *
FROM
  NULL_WITH_AVG
WHERE
  AVG_TEMP_NULL_RATE - TWO_WEEK_ROLLING_AVG > 0.3;
___
$ sqlite3 EXOPLANETS.db < queries/dist-query-rolling-avg.sql
DATE_ADDED|AVG_TEMP_NULL_RATE|TWO_WEEK_ROLLING_AVG
2020-03-09|0.967391304347826|0.436077995611105
2020-06-02|0.929411764705882|0.441299602441599
2020-06-03|0.977011494252874|0.47913211475687
2020-06-04|0.989690721649485|0.515566041654715
2020-06-07|0.987804878048781|0.554753033524633
2020-06-08|0.961904761904762|0.594966974173356
```

==TODO need clean plots for all of these!==

## Schema

Lastly, how do we build a schema detector? Schema changes can be important for root cause analysis, which differentiates observability from mere monitoring.
==TODO add new dbs for updated schema and an `EXOPLANETS_SCHEMA` table to query==

## Lineage