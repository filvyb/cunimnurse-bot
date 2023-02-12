import std/db_postgres

proc initializeDB*(db: DbConn) =
  db.exec(sql"DROP TABLE IF EXISTS scheme")
  db.exec(sql("""CREATE TABLE scheme (
                 id INTEGER UNIQUE)"""))
  db.exec(sql"INSERT INTO scheme(id) VALUES(1)")

  db.exec(sql"DROP TABLE IF EXISTS verification")
  db.exec(sql("""CREATE TABLE verification (
                 id TEXT PRIMARY KEY,
                 login TEXT,
                 code VARCHAR(4),
                 status INTEGER default 0
                 )"""))