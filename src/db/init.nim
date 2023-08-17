import db_connector/db_postgres
import std/strformat

import ../config

let conf = config.conf.database

let db_conn* = open("", conf.user, conf.password, fmt"host={conf.host} port={conf.port} dbname={conf.dbname}")

proc initializeDB*() =
  db_conn.exec(sql"DROP TABLE IF EXISTS verification CASCADE")
  # Status
  # 0 = unverified, 1 = pending, 2 = verified, 3 = banned, 4 = jailed
  # uni_pos
  # 0 = student, 2 = graduate, 3 = teacher, 4 = host
  db_conn.exec(sql("""CREATE TABLE verification (
                 id TEXT PRIMARY KEY,
                 login TEXT UNIQUE,
                 name TEXT,
                 code VARCHAR(12),
                 status INTEGER default 0 CHECK(status >= 0),
                 uni_pos INTEGER default 0 CHECK(uni_pos >= 0),
                 joined TIMESTAMPTZ default NOW(),
                 karma INTEGER default 0
                 )"""))

  #db_conn.exec(sql"CREATE INDEX log_tsv_idx ON verification USING gin(login_tsv)")
  #db_conn.exec(sql"CREATE FUNCTION tsv_update_trigger() RETURNS trigger AS $$ begin new.login_tsv := to_tsvector(new.text); return new; end $$ LANGUAGE plpgsql")
  #db_conn.exec(sql"CREATE TRIGGER tsvectorupdate BEFORE UPDATE ON login FOR EACH ROW WHEN (old.text IS DISTINCT FROM new.text) EXECUTE PROCEDURE tsv_update_trigger()")
  #db_conn.exec(sql"CREATE TRIGGER tsvectorinsert BEFORE INSERT ON login FOR EACH ROW EXECUTE PROCEDURE tsv_update_trigger();")

  db_conn.exec(sql"DROP TABLE IF EXISTS roles CASCADE")
  # Power
  # 0 = unverified, 1 = verified, 2 = mod, 3 = helper, 4 = admin
  db_conn.exec(sql("""CREATE TABLE roles (
                 guild_id TEXT,
                 id TEXT,
                 name TEXT,
                 power INTEGER default 0 CHECK(power >= 0),
                 PRIMARY KEY (guild_id, id)
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS role_ownership CASCADE")
  db_conn.exec(sql("""CREATE TABLE role_ownership (
                 user_id TEXT references verification(id) ON DELETE CASCADE,
                 role_id TEXT,
                 guild_id TEXT,
                 FOREIGN KEY(guild_id, role_id) references roles(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS channels CASCADE")
  db_conn.exec(sql("""CREATE TABLE channels (
                 guild_id TEXT,
                 id TEXT,
                 name TEXT,
                 PRIMARY KEY (guild_id, id)
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS channel_membership CASCADE")
  db_conn.exec(sql("""CREATE TABLE channel_membership (
                 user_id TEXT references verification(id) ON DELETE CASCADE,
                 channel_id TEXT,
                 guild_id TEXT,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS react2role CASCADE")
  db_conn.exec(sql("""CREATE TABLE react2role (
                 guild_id TEXT,
                 emoji_name TEXT NOT NULL,
                 channel_id TEXT,
                 role_id TEXT,
                 message_id TEXT NOT NULL,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE,
                 FOREIGN KEY(guild_id, role_id) references roles(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS react2thread CASCADE")
  db_conn.exec(sql("""CREATE TABLE react2thread (
                 guild_id TEXT,
                 emoji_name TEXT NOT NULL,
                 channel_id TEXT,
                 thread_id TEXT NOT NULL,
                 message_id TEXT NOT NULL,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS react2chan CASCADE")
  db_conn.exec(sql("""CREATE TABLE react2chan (
                 guild_id TEXT,
                 emoji_name TEXT NOT NULL,
                 channel_id TEXT,
                 target_channel_id TEXT,
                 message_id TEXT NOT NULL,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE,
                 FOREIGN KEY(guild_id, target_channel_id) references channels(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS bookmarks CASCADE")
  db_conn.exec(sql("""CREATE TABLE bookmarks (
                 user_id TEXT references verification(id),
                 guild_id TEXT,
                 channel_id TEXT,
                 message_id TEXT NOT NULL,
                 interaction_id TEXT NOT NULL,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS video_links CASCADE")
  db_conn.exec(sql("""CREATE TABLE video_links (
                 subject TEXT NOT NULL,
                 username TEXT NOT NULL,
                 name TEXT NOT NULL,
                 link TEXT NOT NULL
                 )"""))

  db_conn.exec(sql"DROP TABLE IF EXISTS media_dedupe CASCADE")
  db_conn.exec(sql("""CREATE TABLE media_dedupe (
                 guild_id TEXT,
                 channel_id TEXT,
                 message_id TEXT NOT NULL,
                 media_id TEXT NOT NULL,
                 hash TEXT NOT NULL,
                 FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE
                 )"""))


  # Indexes
  db_conn.exec(sql"CREATE INDEX ver_log ON verification (login)")
  db_conn.exec(sql"CREATE INDEX ver_sta ON verification (status)")
  db_conn.exec(sql"CREATE INDEX ver_id_log ON verification (id, login)")
  db_conn.exec(sql"CREATE INDEX ver_id_sta ON verification (id, status)")
  db_conn.exec(sql"CREATE INDEX ver_id_cod ON verification (id, code)")

  db_conn.exec(sql"CREATE INDEX rol_id1 ON roles (guild_id)")
  #db_conn.exec(sql"CREATE INDEX rol_id1_id2 ON roles (guild_id, id)")
  db_conn.exec(sql"CREATE INDEX rol_id2_pow ON roles (id, power)")
  db_conn.exec(sql"CREATE INDEX rol_id1_id2_pow ON roles (guild_id, id, power)")

  db_conn.exec(sql"CREATE INDEX rolown_id1_id2_id3 ON role_ownership (user_id, role_id, guild_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id1_id2 ON role_ownership (user_id, role_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id1 ON role_ownership (user_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id2 ON role_ownership (role_id)")
  db_conn.exec(sql"CREATE INDEX rolown_id3 ON role_ownership (guild_id)")

  db_conn.exec(sql"CREATE INDEX ch_id1 ON channels (guild_id)")
  
  db_conn.exec(sql"CREATE INDEX chmem_id1_id2_id3 ON channel_membership (user_id, channel_id, guild_id)")
  db_conn.exec(sql"CREATE INDEX chmem_id1_id2 ON channel_membership (user_id, channel_id)")
  db_conn.exec(sql"CREATE INDEX chmem_id1 ON channel_membership (user_id)")
  db_conn.exec(sql"CREATE INDEX chmem_id2 ON channel_membership (channel_id)")
  db_conn.exec(sql"CREATE INDEX chmem_id3 ON channel_membership (guild_id)")

  db_conn.exec(sql"CREATE INDEX r2r_id1 ON react2role (guild_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id2 ON react2role (channel_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id3 ON react2role (role_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id4 ON react2role (message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id1_id3_id4 ON react2role (guild_id, role_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_id1_name_id2_id4 ON react2role (guild_id, emoji_name, channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2r_name_id_id2_id3_id4 ON react2role (guild_id, emoji_name, channel_id, role_id, message_id)")

  db_conn.exec(sql"CREATE INDEX r2t_id1 ON react2thread (guild_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id2 ON react2thread (channel_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id3 ON react2thread (thread_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id4 ON react2thread (message_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id3_id4 ON react2thread (thread_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id1_id2_id3_id4 ON react2thread (guild_id, channel_id, thread_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2t_id1_name_id2_id4 ON react2thread (guild_id, emoji_name, channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2t_name_id1_id2_id3_id4 ON react2thread (guild_id, emoji_name, channel_id, thread_id, message_id)")

  db_conn.exec(sql"CREATE INDEX r2c_id1 ON react2chan (guild_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id2 ON react2chan (channel_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id3 ON react2chan (target_channel_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id4 ON react2chan (message_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id3_id4 ON react2chan (target_channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id1_id2_id3_id4 ON react2chan (guild_id, channel_id, target_channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2c_id1_name_id2_id4 ON react2chan (guild_id, emoji_name, channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX r2c_name_id_id2_id3_id4 ON react2chan (guild_id, emoji_name, channel_id, target_channel_id, message_id)")

  db_conn.exec(sql"CREATE INDEX book_id ON bookmarks (user_id)")
  db_conn.exec(sql"CREATE INDEX book_id2 ON bookmarks (guild_id)")
  db_conn.exec(sql"CREATE INDEX book_id3 ON bookmarks (channel_id)")
  db_conn.exec(sql"CREATE INDEX book_id4 ON bookmarks (message_id)")
  db_conn.exec(sql"CREATE INDEX book_id_id3 ON bookmarks (user_id, message_id)")
  db_conn.exec(sql"CREATE INDEX book_id2_id3 ON bookmarks (channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX book_id_id4 ON bookmarks (user_id, interaction_id)")

  db_conn.exec(sql"CREATE INDEX vid_sub ON video_links (subject)")

  db_conn.exec(sql"CREATE INDEX med_id ON media_dedupe (guild_id)")
  db_conn.exec(sql"CREATE INDEX med_id2 ON media_dedupe (channel_id)")
  db_conn.exec(sql"CREATE INDEX med_id3 ON media_dedupe (message_id)")
  db_conn.exec(sql"CREATE INDEX med_hash ON media_dedupe (hash)")
  db_conn.exec(sql"CREATE INDEX med_id2_hash ON media_dedupe (channel_id, hash)")
  db_conn.exec(sql"CREATE INDEX med_id3_hash ON media_dedupe (media_id, hash)")
  db_conn.exec(sql"CREATE INDEX med_id1_id2_hash ON media_dedupe (guild_id, channel_id, hash)")
  db_conn.exec(sql"CREATE INDEX med_id2_id3 ON media_dedupe (channel_id, message_id)")
  db_conn.exec(sql"CREATE INDEX med_id1_id2_id3_id4 ON media_dedupe (guild_id, channel_id, message_id, media_id)")

  db_conn.exec(sql"DROP TABLE IF EXISTS scheme CASCADE")
  db_conn.exec(sql("""CREATE TABLE scheme (
                 id INTEGER UNIQUE)"""))
  db_conn.exec(sql"INSERT INTO scheme(id) VALUES(1)")

proc migrateDB*(scheme: int) =
  var scheme = scheme
  if scheme < 2:
    try:
      db_conn.exec(sql"DROP TABLE IF EXISTS searching CASCADE")
      db_conn.exec(sql("""CREATE TABLE searching (
                    guild_id TEXT,
                    channel_id TEXT,
                    user_id TEXT references verification(id) ON DELETE CASCADE,
                    search_id INTEGER NOT NULL CHECK(search_id >= 0),
                    search TEXT NOT NULL,
                    FOREIGN KEY(guild_id, channel_id) references channels(guild_id, id) ON DELETE CASCADE,
                    UNIQUE(guild_id, channel_id, search_id)
                    )"""))

      db_conn.exec(sql"CREATE INDEX sear_id1 ON searching (guild_id)")
      db_conn.exec(sql"CREATE INDEX sear_id2 ON searching (channel_id)")
      db_conn.exec(sql"CREATE INDEX sear_id3 ON searching (user_id)")
      db_conn.exec(sql"CREATE INDEX sear_id1_id2 ON searching (guild_id, channel_id)")
      db_conn.exec(sql"CREATE INDEX sear_id1_id2_id4 ON searching (guild_id, channel_id, search_id)")

      db_conn.exec(sql"UPDATE scheme SET id = 2 WHERE id = ?", scheme)
      scheme = scheme + 1
    except DbError:
      quit(99)
  if scheme < 3:
    try:
      db_conn.exec(sql"CREATE INDEX med_id1_id2 ON media_dedupe (guild_id, channel_id)")

      db_conn.exec(sql"UPDATE scheme SET id = 3 WHERE id = ?", scheme)
      scheme = scheme + 1
    except DbError:
      quit(99)
  if scheme < 4:
    try:
      db_conn.exec(sql"ALTER TABLE media_dedupe DROP COLUMN hash CASCADE")
      db_conn.exec(sql"ALTER TABLE media_dedupe ADD COLUMN grays vector(256)")

      db_conn.exec(sql"UPDATE scheme SET id = 4 WHERE id = ?", scheme)
      scheme = scheme + 1
    except DbError:
      quit(99)
