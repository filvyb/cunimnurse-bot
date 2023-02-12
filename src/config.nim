import parsetoml

import std/os

type
  DiscordConf* = object of RootObj
    token*: string
    guild_id*: string
  DatabaseConf* = object of RootObj
    host*: string
    port*: string
    user*: string
    password*: string
    dbname*: string
  EmailConf* = object of RootObj
    address*: string
    port*: string
    ssl*: bool
    user*: string
    password*: string
  Config* = object of RootObj
    discord*: DiscordConf
    database*: DatabaseConf
    email*: EmailConf


proc initConfig*(): Config =
  var config_path = ""
  if paramCount() == 0:
    config_path = "config.toml"
  elif paramCount() == 1:
    config_path = paramStr(1)
  else:
    stderr.writeLine("Wrong number of arguments", 1)
    quit(1)
  #echo config_path
  try:
    var x = parsetoml.parseFile(config_path)
    var d = x["discord"]
    result.discord = DiscordConf(token: d["token"].getStr(), guild_id: d["guild_id"].getStr())
    var db = x["database"]
    result.database = DatabaseConf()
    result.database.host = db["host"].getStr()
    result.database.port = db["port"].getStr()
    result.database.user = db["user"].getStr()
    result.database.password = db["password"].getStr()
    result.database.dbname = db["dbname"].getStr()
    var e = x["email"]
    result.email = EmailConf()
    result.email.address = e["address"].getStr()
    result.email.port = e["port"].getStr()
    result.email.ssl = e["ssl"].getBool()
    result.email.user = e["user"].getStr()
    result.email.password = e["password"].getStr()
  except CatchableError as e:
    stderr.writeLine(e.msg)
    quit(99)
