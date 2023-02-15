import std/db_postgres
import std/strutils
import std/options
import std/sequtils

from init import db_conn

var db = db_conn

proc check_scheme*(): string =
  var ret: string
  try:
    ret = db.getValue(sql"SELECT ? FROM scheme", "*")
  except DbError as e:
    stderr.writeLine(e.msg)
    ret = ""
  return ret

proc insert_user*(id: string, login: string, stat: int): bool =
  try:
    db.exec(sql"INSERT INTO verification (id, login, status) VALUES (?, ?, ?)",
        id, login, stat)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc insert_code*(login: string, code: string): bool =
  try:
    db.exec(sql"UPDATE verification SET code = ? WHERE login = ?",
        code, login)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc update_verified_status*(login: string, stat: int): bool =
  try:
    db.exec(sql"UPDATE verification SET status = ? WHERE login = ?",
        stat, login)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc get_user_verification_status*(id: string): int =
  try:
    var res = db.getValue(sql"SELECT status FROM verification WHERE id = ?", id)
    if res == "":
      return -1
    return parseInt(res)
  except DbError as e:
    stderr.writeLine(e.msg)
    return -1

proc get_user_verification_code*(id: string): string =
  try:
    var res = db.getValue(sql"SELECT code FROM verification WHERE id = ?", id)
    return res
  except DbError as e:
    stderr.writeLine(e.msg)
    return ""

proc insert_role*(id: string, name: string, power: int): bool =
  try:
    db.exec(sql"INSERT INTO roles (id, name, power) VALUES (?, ?, ?)",
        id, name, power)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc update_role_name*(id: string, name: string): bool =
  try:
    db.exec(sql"UPDATE roles SET name = ? WHERE id = ?",
        name, id)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc update_role_power*(id: string, power: int): bool =
  try:
    db.exec(sql"UPDATE roles SET power = ? WHERE id = ?",
        power, id)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc get_role*(id: string): Option[seq[string]] =
  try:
    var res = db.getRow(sql"SELECT * FROM roles where id = ?", id)

    var ret = @[res[0], res[1], res[2]]

    return some(ret)
  except DbError as e:
    stderr.writeLine(e.msg)
    return none(seq[string])

proc get_role_bool*(id: string): bool =
  try:
    var res = get_role(id).get()
    if res[0] == "" and res[1] == "" and res[2] == "":
      return false
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false

proc get_all_roles*(): Option[seq[Row]] =
  try:
    var res = db.getAllRows(sql"SELECT id, name FROM roles")
    if res.len == 0:
      return none(seq[Row])
    return some(res)
  except DbError as e:
    stderr.writeLine(e.msg)
    return none(seq[Row])

proc delete_role*(id: string): bool =
  try:
    db.exec(sql"DELETE FROM roles WHERE id = ?",
        id)
    return true
  except DbError as e:
    stderr.writeLine(e.msg)
    return false
