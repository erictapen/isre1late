#! /usr/bin/env python3

import psycopg2
import hashlib

conn = psycopg2.connect()

cursor = conn.cursor("some_unique_name")
cursor.execute("SELECT url, fetched_at, body FROM fetched_json limit 10000;")
for url, fetched_at, body in cursor:
    file_id = (url + str(fetched_at)).encode(encoding = 'UTF-8', errors = 'strict')
    m = hashlib.sha256()
    m.update(file_id)
    file_name = m.hexdigest() + ".py"
    with open("data/" + file_name, 'w') as f:
       f.write(body)
