import std/db_postgres
import std/strformat

import ../config

let conf = config.conf.database

let db_conn* = open("", conf.user, conf.password, fmt"host={conf.host} port={conf.port} dbname={conf.dbname}")

proc initializeDB*() =
  db_conn.exec(sql"DROP TABLE IF EXISTS scheme CASCADE")
  db_conn.exec(sql("""CREATE TABLE scheme (
                 id INTEGER UNIQUE)"""))
  db_conn.exec(sql"INSERT INTO scheme(id) VALUES(1)")

  db_conn.exec(sql"DROP TABLE IF EXISTS verification CASCADE")
  # Status
  # 0 = unverified, 1 = pending, 2 = verified, 3 = banned
  db_conn.exec(sql("""CREATE TABLE verification (
                 id TEXT PRIMARY KEY,
                 login TEXT,
                 code VARCHAR(12),
                 status INTEGER default 0
                 )"""))

  # Indexes
  db_conn.exec(sql"CREATE INDEX ver_id_log ON verification (id, login);")
  db_conn.exec(sql"CREATE INDEX ver_id_sta ON verification (id, status);")
  db_conn.exec(sql"CREATE INDEX ver_id_cod ON verification (id, code);")
