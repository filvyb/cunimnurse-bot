import std/db_postgres

from init import db_conn

var db = db_conn

proc check_scheme*(): string =
  var ret: string
  try:
    ret = getValue(db, sql"SELECT ? FROM scheme", "*")
  except:
    ret = ""
  return ret

proc insert_user*(id: string, login: string, stat: int): bool =
  try:    
    db.exec(sql"INSERT INTO verification (id, login, status) VALUES (?, ?, ?)",
        id, login, stat)
    return true
  except:
    return false

proc insert_code*(login: string, code: string): bool =
  try:    
    db.exec(sql"UPDATE verification SET code = ? WHERE login = ?",
        code, login)
    return true
  except:
    return false

proc update_verified_status*(login: string, stat: int): bool =
  try:    
    db.exec(sql"UPDATE verification SET code = ? WHERE login = ?",
        stat, login)
    return true
  except:
    return false