import parsetoml

import std/os

type
  DiscordConf* = object of RootObj
    token*: string
    guild_id*: string
    verify_channel*: string
    verified_role*: string
  DatabaseConf* = object of RootObj
    host*: string
    port*: string
    user*: string
    password*: string
    dbname*: string
  EmailConf* = object of RootObj
    address*: string
    port*: uint16
    ssl*: bool
    user*: string
    password*: string
  Config* = object of RootObj
    discord*: DiscordConf
    database*: DatabaseConf
    email*: EmailConf


proc initConfig(): Config =
  var config_path = ""
  if paramCount() == 0:
    config_path = "config.toml"
  elif paramCount() == 1:
    config_path = paramStr(1)
  else:
    stderr.writeLine("Wrong number of arguments", 1)
    quit(1)

  try:
    var x = parsetoml.parseFile(config_path)
    var d = x["discord"]
    result.discord = DiscordConf()
    result.discord.token = d["token"].getStr()
    result.discord.guild_id = d["guild_id"].getStr()
    result.discord.verify_channel = d["verify_channel"].getStr()
    result.discord.verified_role = d["verified_role"].getStr()

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
    result.email.port = uint16(e["port"].getInt())
    result.email.ssl = e["ssl"].getBool()
    result.email.user = e["user"].getStr()
    result.email.password = e["password"].getStr()

  except CatchableError as e:
    stderr.writeLine("Can't load config")
    stderr.writeLine(e.msg)
    quit(99)

let conf* = initConfig()
