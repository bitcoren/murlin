#!/usr/bin/env python3

import feedparser
from fdb import connect

con = connect(host='localhost', database='/opt/murzilla/data/rss.fdb', user='sysdba', password='murzilla')
cur = con.cursor()

# Check if table exists
cur.execute("SELECT RDB$RELATION_NAME FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = 'RSS_ITEMS'")
table_exists = cur.fetchone() is not None

if not table_exists:
    print("Table is not exists")
    # Create table
    cur.execute("CREATE TABLE RSS_ITEMS (TITLE VARCHAR(1024), LINK VARCHAR(1024), PUBLISHED VARCHAR(1024))")
    con.commit()

with open('/opt/murzilla/data/feeds.txt') as f:
    feeds = f.read().splitlines()

for feed_url in feeds:
    feed = feedparser.parse(feed_url)
    for entry in feed.entries:
        title = entry.title
        link = entry.link
        published = entry.published
        cur.execute("INSERT INTO RSS_ITEMS (TITLE, LINK, PUBLISHED) VALUES (?,?,?)", (title, link, published))

con.commit()
cur.close()
con.close()
