import db_connector/db_postgres
import std/strutils
import std/options
import std/sequtils
import std/logging
import std/times

from init import db_conn
import ../utils/logging as clogger
import ../utils/data_structs

var db = db_conn

proc check_scheme*(): string =
  var ret: string
  try:
    ret = db.getValue(sql"SELECT * FROM scheme")
    return ret
  except DbError as e:
    error(e.msg)
    ret = ""
  return ret


# User queries
proc insert_user*(id, login: string, stat: int): bool =
  try:
    db.exec(sql"INSERT INTO verification (id, login, status) VALUES (?, ?, ?)",
        id, login, stat)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_code*(login, code: string): bool =
  try:
    db.exec(sql"UPDATE verification SET code = ? WHERE login = ?",
        code, login)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_verified_status*(id: string, stat: int): bool =
  try:
    db.exec(sql"UPDATE verification SET status = ? WHERE id = ?",
        stat, id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_verified_status_login*(login: string, stat: int): bool =
  try:
    db.exec(sql"UPDATE verification SET status = ? WHERE login = ?",
        stat, login)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_user_position*(id: string, pos: int): bool =
  try:
    db.exec(sql"UPDATE verification SET uni_pos = ? WHERE id = ?",
        pos, id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_user_info*(id, name: string, faculty: Faculty, study_type, study_branch: string, year, circle: int): bool =
  try:
    db.exec(sql"UPDATE verification SET name = ?, faculty = ?, study_type = ?, study_branch = ?, year = ?, circle = ? WHERE id = ?",
        name, ord(faculty), study_type, study_branch, year, circle, id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_user_verification_status*(id: string): int =
  try:
    var res = db.getValue(sql"SELECT status FROM verification WHERE id = ?", id)
    if res == "":
      return -1
    return parseInt(res)
  except DbError as e:
    error(e.msg)
    return -1

proc get_user_verification_code*(id: string): string =
  try:
    var res = db.getValue(sql"SELECT code FROM verification WHERE id = ?", id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

#[
proc get_verified_users*(): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT id FROM verification WHERE status = 2")
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])


proc get_user*(id: string): Option[seq[string]] =
  try:
    var res = db.getRow(sql"SELECT * FROM verification WHERE id = ?", id)

    if res[0] == "":
      return none(seq[string])
    
    var ret = @[res[0], res[1], res[2], res[3], res[4], res[5], res[6], res[7]]

    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(seq[string])
  ]#


proc get_user*(id: string): Option[DbUser] =
  try:
    var res = db.getRow(sql"SELECT login, name, code, status, uni_pos, joined, karma, faculty, study_type, study_branch, year, circle FROM verification WHERE id = ?", id)

    if res[0] == "":
      return none(DbUser)

    var ret = DbUser()
    
    ret.id = id
    ret.login = res[0]
    ret.name = res[1]
    ret.code = res[2]
    ret.status = VerStatus(parseInt(res[3]))
    ret.uni_pos = parseInt(res[4])
    try:
      ret.joined = parse(res[5], "YYYY-MM-dd HH:mm:ss'.'ffffffzz")
    except CatchableError as e:
      error("Error parsing date: " & res[5] &  "\n" & e.msg)
    ret.karma = parseInt(res[6])
    ret.faculty = Faculty(parseInt(res[7].strip()))
    ret.study_type = res[8]
    ret.study_branch = res[9]
    ret.year = parseInt(res[10])
    ret.circle = parseInt(res[11])

    return some(ret)

  except DbError as e:
    error(e.msg)
    return none(DbUser)

proc get_verified_users*(): Option[seq[DbUser]] =
  try:
    var tmp = db.getAllRows(sql"SELECT id, login, name, code, status, uni_pos, joined, karma, faculty, study_type, study_branch, year, circle FROM verification WHERE status = 2")
    if tmp.len == 0:
      return none(seq[DbUser])
    
    var res: seq[DbUser]
    for x in tmp:
      var ret = DbUser()
      ret.id = x[0]
      ret.login = x[1]
      ret.name = x[2]
      ret.code = x[3]
      ret.status = VerStatus(parseInt(x[4]))
      ret.uni_pos = parseInt(x[5])
      try:
        ret.joined = parse(x[6], "YYYY-MM-dd HH:mm:ss'.'ffffffzz")
      except CatchableError as e:
        error("Error parsing date: " & x[6] & "\n" & e.msg)
      ret.karma = parseInt(x[7])
      ret.faculty = Faculty(parseInt(x[8].strip()))
      ret.study_type = x[9]
      ret.study_branch = x[10]
      ret.year = parseInt(x[11])
      ret.circle = parseInt(x[12])
      res &= ret

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[DbUser])

proc delete_user*(id: string): bool =
  try:
    db.exec(sql"DELETE FROM verification WHERE id = ?",
        id)
    return true
  except DbError as e:
    error(e.msg)
    return false


# Role queries
proc insert_role*(guild_id, id, name: string, power: int): bool =
  try:
    db.exec(sql"INSERT INTO roles (guild_id, id, name, power) VALUES (?, ?, ?, ?)",
        guild_id, id, name, power)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_role_name*(guild_id, id, name: string): bool =
  try:
    db.exec(sql"UPDATE roles SET name = ? WHERE id = ? AND guild_id = ?",
        name, id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_role_power*(guild_id, id: string, power: int): bool =
  try:
    db.exec(sql"UPDATE roles SET power = ? WHERE id = ? AND guild_id = ?",
        power, id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_role*(guild_id, id: string): Option[seq[string]] =
  try:
    var res = db.getRow(sql"SELECT id, name, power FROM roles WHERE id = ? AND guild_id = ?",
        id, guild_id)

    var ret = @[res[0], res[1], res[2]]

    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc get_role_bool*(guild_id, id: string): bool =
  try:
    var res = get_role(guild_id, id).get()
    if res[0] == "" and res[1] == "" and res[2] == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_role_id_name*(guild_id, name: string): Option[string] =
  try:
    var res = db.getValue(sql"SELECT id FROM roles WHERE name = ? AND guild_id = ?",
        name, guild_id)

    if res == "":
      return none(string)

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(string)

proc get_all_roles*(guild_id: string): Option[seq[Row]] =
  try:
    var res = db.getAllRows(sql"SELECT id, name FROM roles WHERE guild_id = ?",
        guild_id)
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[Row])

proc delete_role*(guild_id, id: string): bool =
  try:
    db.exec(sql"DELETE FROM roles WHERE id = ? AND guild_id = ?",
        id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_user_power_level*(guild_id, id: string): int =
  try:
    var res = db.getValue(sql"SELECT r.power FROM roles r, role_ownership o WHERE o.user_id = ? AND o.guild_id = ? GROUP BY r.power ORDER BY r.power DESC",
        id, guild_id)
    if res == "":
      return -1
    return parseInt(res)
  except DbError as e:
    error(e.msg)
    return -1


# Role relation queries
proc insert_role_relation*(guild_id, user_id, role_id: string): bool =
  try:
    db.exec(sql"INSERT INTO role_ownership (user_id, role_id, guild_id) VALUES (?, ?, ?)",
        user_id, role_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc exists_role_relation*(guild_id, user_id, role_id: string): bool =
  try:
    var res = db.getValue(sql"SELECT * FROM role_ownership WHERE user_id = ? AND role_id = ? AND guild_id = ?",
        user_id, role_id, guild_id)
    if res == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_role_users*(guild_id, role_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT user_id FROM role_ownership WHERE role_id = ? AND guild_id = ?",
        role_id, guild_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc get_all_user_roles*(guild_id, user_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT role_id FROM role_ownership WHERE user_id = ? AND guild_id = ?",
        user_id, guild_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc delete_role_relation*(guild_id, user_id, role_id: string): bool =
  try:
    db.exec(sql"DELETE FROM role_ownership WHERE user_id = ? AND role_id = ? AND guild_id = ?",
        user_id, role_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_all_user_role_relation*(guild_id, user_id: string): bool =
  try:
    db.exec(sql"DELETE FROM role_ownership WHERE user_id = ? AND guild_id = ?",
        user_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false


# React2role queries
proc insert_role_reaction*(guild_id, emoji_name, channel_id, role_id, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO react2role (guild_id, emoji_name, channel_id, role_id, message_id) VALUES (?, ?, ?, ?, ?)",
        guild_id, emoji_name, channel_id, role_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_reaction_role*(guild_id, emoji_name, channel_id, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT role_id FROM react2role WHERE emoji_name = ? AND channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, message_id, guild_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc delete_role_reaction*(guild_id, emoji_name, channel_id, role_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2role WHERE emoji_name = ? AND channel_id = ? AND role_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, role_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_role_emoji_reaction*(guild_id, emoji_name, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2role WHERE emoji_name = ? AND channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_reaction_message*(guild_id, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2role WHERE channel_id = ? AND message_id = ? AND guild_id = ?",
        channel_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

# React2thread queries
proc insert_thread_reaction*(guild_id, emoji_name, channel_id, thread_id, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO react2thread (guild_id, emoji_name, channel_id, thread_id, message_id) VALUES (?, ?, ?, ?, ?)",
        guild_id, emoji_name, channel_id, thread_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_reaction_thread*(guild_id, emoji_name, channel_id, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT thread_id FROM react2thread WHERE emoji_name = ? AND channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, message_id, guild_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc get_react_msg_by_thread*(guild_id, channel_id, thread_id: string): Option[(string, string)] =
  try:
    var res = db.getRow(sql"SELECT message_id, emoji_name FROM react2thread WHERE channel_id = ? AND thread_id = ? AND guild_id = ?",
        channel_id, thread_id, guild_id)
    if res[0] == "":
      return none (string, string)
    return some (res[0], res[1])
  except DbError as e:
    error(e.msg)
    return none (string, string)

proc get_threads_by_message*(guild_id, channel_id, message_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT thread_id FROM react2thread WHERE channel_id = ? AND guild_id = ? AND message_id = ?",
        channel_id, guild_id, message_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc delete_reaction2thread_message*(guild_id, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2thread WHERE channel_id = ? AND message_id = ? AND guild_id = ?",
        channel_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_reaction_thread*(guild_id, thread_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2thread WHERE thread_id = ? AND guild_id = ?",
        thread_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

# Channel queries
proc insert_channel*(guild_id, channel_id: string, name = ""): bool =
  try:
    db.exec(sql"INSERT INTO channels (guild_id, id, name) VALUES (?, ?, ?)",
        guild_id, channel_id, name)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_channels*(guild_id: string): Option[seq[Row]] =
  try:
    var res = db.getAllRows(sql"SELECT id, name FROM channels WHERE guild_id = ?", guild_id)
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[Row])

proc exists_channel*(guild_id, channel_id: string): bool =
  try:
    var res = db.getValue(sql"SELECT * FROM channels WHERE channels = ? AND guild_id = ?",
        channel_id, guild_id)
    if res == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_channel*(guild_id, channel_id: string): bool =
  try:
    db.exec(sql"DELETE FROM channels WHERE id = ? AND guild_id = ?",
        channel_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

# Channel membership queries
proc insert_channel_membership*(guild_id, user_id, channel_id: string): bool =
  try:
    db.exec(sql"INSERT INTO channel_membership (user_id, channel_id, guild_id) VALUES (?, ?, ?)",
        user_id, channel_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc exists_channel_membership*(guild_id, user_id, channel_id: string): bool =
  try:
    var res = db.getValue(sql"SELECT * FROM channel_membership WHERE user_id = ? AND channel_id = ? AND guild_id = ?",
        user_id, channel_id, guild_id)
    if res == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_channel_users*(guild_id, channel_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT user_id FROM channel_membership WHERE channel_id = ? AND guild_id = ?",
        channel_id, guild_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc get_all_user_channels*(guild_id, user_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT channel_id FROM channel_membership WHERE user_id = ? AND guild_id = ?",
        user_id, guild_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc delete_channel_membership*(guild_id, user_id, channel_id: string): bool =
  try:
    db.exec(sql"DELETE FROM channel_membership WHERE user_id = ? AND channel_id = ? AND guild_id = ?",
        user_id, channel_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_all_user_channel_membership*(guild_id, user_id: string): bool =
  try:
    db.exec(sql"DELETE FROM channel_membership WHERE user_id = ? AND guild_id = ?",
        user_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false


# React2chan queries
proc insert_chan_reaction*(guild_id, emoji_name, channel_id, target_id, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO react2chan (guild_id, emoji_name, channel_id, target_channel_id, message_id) VALUES (?, ?, ?, ?, ?)",
        guild_id, emoji_name, channel_id, target_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_reaction_chan*(guild_id, emoji_name, channel_id, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT target_channel_id FROM react2chan WHERE emoji_name = ? AND channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, message_id, guild_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc delete_chan_reaction*(guild_id, emoji_name, channel_id, target_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2chan WHERE emoji_name = ? AND channel_id = ? AND target_channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, target_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_chan_emoji_reaction*(guild_id, emoji_name, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2chan WHERE emoji_name = ? AND channel_id = ? AND message_id = ? AND guild_id = ?",
        emoji_name, channel_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_chan_react_message*(guild_id, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2chan WHERE channel_id = ? AND message_id = ? AND guild_id = ?",
        channel_id, message_id, guild_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

# Queries for searches
proc insert_search*(guild_id, channel_id, user_id: string, search_id: int, search: string): bool =
  try:
    db.exec(sql"INSERT INTO searching (guild_id, channel_id, user_id, search_id, search) VALUES (?, ?, ?, ?, ?)",
        guild_id, channel_id, user_id, search_id, search)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_channel_searches*(guild_id, channel_id: string): Option[seq[Row]] =
  try:
    var res = db.getAllRows(sql"SELECT user_id, search_id, search FROM searching WHERE guild_id = ? AND channel_id = ?",
        guild_id, channel_id)
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[Row])

proc get_last_channel_search_id*(guild_id, channel_id: string): int =
  try:
    var res = db.getValue(sql"SELECT search_id FROM searching WHERE guild_id = ? AND channel_id = ? GROUP BY search_id ORDER BY search_id DESC",
        guild_id, channel_id)
    if res == "":
      return 0
    return parseInt(res)
  except DbError as e:
    error(e.msg)
    return -1

proc get_search_id_user*(guild_id, channel_id: string, search_id: int): string =
  try:
    var res = db.getValue(sql"SELECT search_id FROM searching WHERE guild_id = ? AND channel_id = ? AND search_id = ?",
        guild_id, channel_id, search_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc delete_search*(guild_id, channel_id: string, search_id: int): bool =
  try:
    db.exec(sql"DELETE FROM searching WHERE guild_id = ? AND channel_id = ? AND search_id = ?",
        guild_id, channel_id, search_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

# Queries for media dedupe
proc insert_media*(guild_id, channel_id, message_id, media_id: string, grays: seq[uint8]): bool = 
  var invec = "[" & grays.join(",") & "]"
  try:
    db.exec(sql"INSERT INTO media_dedupe (guild_id, channel_id, message_id, media_id, grays) VALUES (?, ?, ?, ?, ?)",
        guild_id, channel_id, message_id, media_id, invec)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_channel_media*(guild_id, channel_id: string): Option[seq[Row]] {.deprecated.} =
  try:
    var res = db.getAllRows(sql"SELECT message_id, media_id, grays FROM media_dedupe WHERE guild_id = ? AND channel_id = ?", guild_id, channel_id)
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[Row])

proc get_media_distance*(guild_id, channel_id: string, grays: seq[uint8]): Option[array[3,string]] =
  var invec = "[" & grays.join(",") & "]"
  try:
    var res = db.getRow(sql"SELECT message_id, media_id, grays <-> ? AS distance FROM media_dedupe WHERE guild_id = ? AND channel_id = ? ORDER BY distance LIMIT 1",
        invec, guild_id, channel_id)
    if res[0] == "":
      return none(array[3, string])
    var ret = [res[0], res[1], res[2]]
    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(array[3, string])

proc delete_media_message*(guild_id, channel_id, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM media_dedupe WHERE guild_id = ? AND channel_id = ? AND message_id = ?",
        guild_id, channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_pin_sum_msg*(guild_id, channel_id, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO pin_summary (guild_id, channel_id, message_id) VALUES (?, ?, ?)",
        guild_id, channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

#[proc get_pin_sum_time*(guild_id, channel_id, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT last_summary FROM pin_summary WHERE guild_id = ? AND channel_id = ? AND message_id = ? LIMIT 1",
        guild_id, channel_id, message_id)
    
  except DbError as e:
    error(e.msg)
    return ""]#


# Queries for sauces
proc insert_sauce_image*(guild_id, channel_id, message_id, media_id, grays: seq[uint8]): bool = 
  var invec = "[" & grays.join(",") & "]"
  try:
    db.exec(sql"INSERT INTO sauces (guild_id, channel_id, message_id, media_id, grays) VALUES (?, ?, ?, ?, ?)",
        guild_id, channel_id, message_id, media_id, invec)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_sauce_image_full*(guild_id, channel_id, message_id, media_id, grays: seq[uint8], sauce: string, tags: seq[string]): bool = 
  var invec = "[" & grays.join(",") & "]"
  var intags = "[" & tags.join(",") & "]"
  try:
    db.exec(sql"INSERT INTO sauces (guild_id, channel_id, message_id, media_id, grays, sauce, tags, scanned) VALUES (?, ?, ?, ?, ?, ?, ?, true)",
        guild_id, channel_id, message_id, media_id, invec, sauce, intags)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_sauce_image*(guild_id, channel_id, message_id, sauce: string, tags: seq[string]): bool = 
  var intags = "[" & tags.join(",") & "]"
  try:
    db.exec(sql"UPDATE sauces SET sauce = ?, tags = ?, scanned = true WHERE guild_id = ? AND channel_id = ? AND message_id = ?",
        sauce, intags, guild_id, channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_sauce_image_allowed*(guild_id, channel_id, message_id: string, allowed: bool): bool = 
  try:
    db.exec(sql"UPDATE sauces SET allowed = ? WHERE guild_id = ? AND channel_id = ? AND message_id = ?",
        allowed, guild_id, channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_sauce_image*(guild_id, channel_id, message_id: string): Option[array[3, string]] =
  try:
    var res = db.getRow(sql"SELECT media_id, sauce, tags FROM sauces WHERE guild_id = ? AND channel_id = ? AND message_id = ?",
        guild_id, channel_id, message_id)
    if res[0] == "":
      return none(array[3, string])
    var ret = [res[0], res[1], res[2]]
    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(array[3, string])

proc get_sauce_image_distance*(guild_id, channel_id: string, grays: seq[uint8]): Option[array[3, string]] =
  var invec = "[" & grays.join(",") & "]"
  try:
    var res = db.getRow(sql"SELECT message_id, media_id, grays <-> ? AS distance FROM sauces WHERE guild_id = ? AND channel_id = ? ORDER BY distance LIMIT 1",
        invec, guild_id, channel_id)
    if res[0] == "":
      return none(array[3, string])
    var ret = [res[0], res[1], res[2]]
    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(array[3, string])
