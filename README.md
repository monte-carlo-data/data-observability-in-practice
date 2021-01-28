# data-observability-in-practice
Source code for the MC technical blog post ["Data Observability: Building Your Own Data Quality Monitors Using SQL"](https://towardsdatascience.com/data-observability-in-practice-using-sql-755dc6421f59).

# Setting Up Locally
This repository runs `python 3.7.5`. To set up, it's best to run a virtual environment. I do so with `venv`:
```
$ python3 -m venv env
$ source env/bin/activate
$ pip install -r requirements.txt
```

Then, you can run `$ jupyter notebook` to see the plots generated for the blog post.

# Running Queries

The database `EXOPLANETS.db` is set up to run `sqlite3.32.3`. You can call:
```
$ sqlite3 EXOPLANETS.db
```
To interact with the environment, or
```
$ sqlite3 EXOPLANETS.db < queries/{freshness|distribution}/{query}.sql
```
to run one of the queries displayed in the article.

Please feel free to submit issues!
