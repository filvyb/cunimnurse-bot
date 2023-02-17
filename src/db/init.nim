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
  # 0 = unverified, 1 = pending, 2 = verified, 3 = banned, 4 = jailed
  db_conn.exec(sql("""CREATE TABLE verification (
                 id TEXT PRIMARY KEY,
                 login TEXT UNIQUE,
                 code VARCHAR(12),
                 status INTEGER default 0 CHECK(status >= 0)
                 )"""))

  #db_conn.exec(sql"CREATE INDEX log_tsv_idx ON verification USING gin(login_tsv)")
  #db_conn.exec(sql"CREATE FUNCTION tsv_update_trigger() RETURNS trigger AS $$ begin new.login_tsv := to_tsvector(new.text); return new; end $$ LANGUAGE plpgsql")
  #db_conn.exec(sql"CREATE TRIGGER tsvectorupdate BEFORE UPDATE ON login FOR EACH ROW WHEN (old.text IS DISTINCT FROM new.text) EXECUTE PROCEDURE tsv_update_trigger()")
  #db_conn.exec(sql"CREATE TRIGGER tsvectorinsert BEFORE INSERT ON login FOR EACH ROW EXECUTE PROCEDURE tsv_update_trigger();")

  db_conn.exec(sql"DROP TABLE IF EXISTS roles CASCADE")
  # Power
  # 0 = unverified, 1 = verified, 2 = mod, 3 = admin
  db_conn.exec(sql("""CREATE TABLE roles (
                 id TEXT PRIMARY KEY,
                 name TEXT,
                 power INTEGER default 0 CHECK(power >= 0)
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS role_ownership CASCADE")
  db_conn.exec(sql("""CREATE TABLE role_ownership (
                 user_id TEXT references verification(id) ON DELETE CASCADE,
                 role_id TEXT references roles(id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS react2role CASCADE")
  db_conn.exec(sql("""CREATE TABLE react2role (
                 emoji_name TEXT,
                 role_id TEXT references roles(id) ON DELETE CASCADE,
                 message_id TEXT
                 )"""))


  # Indexes
  db_conn.exec(sql"CREATE INDEX ver_log ON verification (login)")
  db_conn.exec(sql"CREATE INDEX ver_sta ON verification (status)")
  db_conn.exec(sql"CREATE INDEX ver_id_log ON verification (id, login)")
  db_conn.exec(sql"CREATE INDEX ver_id_sta ON verification (id, status)")
  db_conn.exec(sql"CREATE INDEX ver_id_cod ON verification (id, code)")

  db_conn.exec(sql"CREATE INDEX rol_id_per ON roles (id, power)")

  db_conn.exec(sql"CREATE INDEX rolown_id_id ON role_ownership (user_id, role_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id1 ON role_ownership (user_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id2 ON role_ownership (role_id)")

  db_conn.exec(sql"CREATE INDEX r2r_id ON react2role (role_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id2 ON react2role (message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id_id2 ON react2role (role_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_name_id2 ON react2role (emoji_name, message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_name_id_id2 ON react2role (emoji_name, role_id, message_id)")
