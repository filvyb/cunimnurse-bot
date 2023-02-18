import std/db_postgres
import std/strutils
import std/options
import std/sequtils
import std/logging

from init import db_conn
import logging as clogger

var db = db_conn

proc check_scheme*(): string =
  var ret: string
  try:
    ret = db.getValue(sql"SELECT ? FROM scheme", "*")
  except DbError as e:
    error(e.msg)
    ret = ""
  return ret

proc insert_user*(id: string, login: string, stat: int): bool =
  try:
    db.exec(sql"INSERT INTO verification (id, login, status) VALUES (?, ?, ?)",
        id, login, stat)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_code*(login: string, code: string): bool =
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

proc delete_user*(id: string): bool =
  try:
    db.exec(sql"DELETE FROM verification WHERE id = ?",
        id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_role*(id: string, name: string, power: int): bool =
  try:
    db.exec(sql"INSERT INTO roles (id, name, power) VALUES (?, ?, ?)",
        id, name, power)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_role_name*(id: string, name: string): bool =
  try:
    db.exec(sql"UPDATE roles SET name = ? WHERE id = ?",
        name, id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc update_role_power*(id: string, power: int): bool =
  try:
    db.exec(sql"UPDATE roles SET power = ? WHERE id = ?",
        power, id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_role*(id: string): Option[seq[string]] =
  try:
    var res = db.getRow(sql"SELECT * FROM roles where id = ?", id)

    var ret = @[res[0], res[1], res[2]]

    return some(ret)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc get_role_bool*(id: string): bool =
  try:
    var res = get_role(id).get()
    if res[0] == "" and res[1] == "" and res[2] == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_roles*(): Option[seq[Row]] =
  try:
    var res = db.getAllRows(sql"SELECT id, name FROM roles")
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[Row])

proc delete_role*(id: string): bool =
  try:
    db.exec(sql"DELETE FROM roles WHERE id = ?",
        id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_user_power_level*(id: string): int =
  try:
    var res = db.getValue(sql"SELECT r.power FROM roles r, role_ownership o WHERE o.user_id = ? GROUP BY r.power ORDER BY r.power DESC", id)
    if res == "":
      return -1
    return parseInt(res)
  except DbError as e:
    error(e.msg)
    return -1

proc insert_role_relation*(user_id: string, role_id: string): bool =
  try:
    db.exec(sql"INSERT INTO role_ownership (user_id, role_id) VALUES (?, ?)",
        user_id, role_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc exists_role_relation*(user_id: string, role_id: string): bool =
  try:
    var res = db.getValue(sql"SELECT * FROM role_ownership WHERE user_id = ? AND role_id = ?",
        user_id, role_id)
    if res == "":
      return false
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_all_user_roles*(user_id: string): Option[seq[string]] =
  try:
    var tmp = db.getAllRows(sql"SELECT role_id FROM role_ownership WHERE user_id = ?", user_id)
    if tmp.len == 0:
      return none(seq[string])
    
    var res: seq[string]
    for x in tmp:
      res.add(x[0])

    return some(res)
  except DbError as e:
    error(e.msg)
    return none(seq[string])

proc delete_role_relation*(user_id: string, role_id: string): bool =
  try:
    db.exec(sql"DELETE FROM role_ownership WHERE user_id = ? AND role_id = ?",
        user_id, role_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_all_user_role_relation*(user_id: string): bool =
  try:
    db.exec(sql"DELETE FROM role_ownership WHERE user_id = ?",
        user_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_role_reaction*(emoji_name: string, channel_id: string, role_id: string, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO react2role (emoji_name, channel_id, role_id, message_id) VALUES (?, ?, ?, ?)",
        emoji_name, channel_id, role_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_reaction_role*(emoji_name: string, channel_id: string, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT role_id FROM react2role WHERE emoji_name = ? AND channel_id = ? AND message_id = ?", emoji_name, channel_id, message_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc delete_role_reaction*(emoji_name: string, channel_id: string, role_id: string, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2role WHERE emoji_name = ? AND channel_id = ? AND role_id = ? AND message_id = ?",
        emoji_name, channel_id, role_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_reaction_message*(channel_id: string, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2role WHERE channel_id = ? AND message_id = ?",
        channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc insert_thread_reaction*(emoji_name: string, channel_id: string, thread_id: string, message_id: string): bool =
  try:
    db.exec(sql"INSERT INTO react2thread (emoji_name, channel_id, thread_id, message_id) VALUES (?, ?, ?, ?)",
        emoji_name, channel_id, thread_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc get_reaction_thread*(emoji_name: string, channel_id: string, message_id: string): string =
  try:
    var res = db.getValue(sql"SELECT thread_id FROM react2thread WHERE emoji_name = ? AND channel_id = ? AND message_id = ?", emoji_name, channel_id, message_id)
    return res
  except DbError as e:
    error(e.msg)
    return ""

proc delete_reaction2thread_message*(channel_id: string, message_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2thread WHERE channel_id = ? AND message_id = ?",
        channel_id, message_id)
    return true
  except DbError as e:
    error(e.msg)
    return false

proc delete_reaction_thread*(thread_id: string): bool =
  try:
    db.exec(sql"DELETE FROM react2thread WHERE thread_id = ?",
        thread_id)
    return true
  except DbError as e:
    error(e.msg)
    return false
