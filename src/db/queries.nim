import std/db_postgres
import std/strutils

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
