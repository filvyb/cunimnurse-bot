import parsetoml

import std/os

type
  DiscordConf* = object of RootObj
    token*: string
    guild_id*: string
    verify_channel*: string
    reaction_channels*: seq[string]
    thread_react_channels*: seq[string]
    verified_role*: string
    moderator_role*: string
    admin_role*: string
    pin_vote_count*: int
  DatabaseConf* = object of RootObj
    host*: string
    port*: string
    user*: string
    password*: string
    dbname*: string
  EmailConf* = object of RootObj
    verify_domain*: string
    address*: string
    port*: uint16
    ssl*: bool
    user*: string
    password*: string
  LogConf* = object of RootObj
    path*: string
  Config* = object of RootObj
    discord*: DiscordConf
    database*: DatabaseConf
    email*: EmailConf
    log*: LogConf


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
    result.discord.moderator_role = d["moderator_role"].getStr()
    result.discord.admin_role = d["admin_role"].getStr()
    var tmp = d["reaction_channels"].getElems()
    var tmpseq: seq[string]
    for x in tmp:
      tmpseq.add(x.getStr())
    result.discord.reaction_channels = tmpseq
    var tmp2 = d["thread_react_channels"].getElems()
    var tmpseq2: seq[string]
    for x in tmp2:
      tmpseq2.add(x.getStr())
    result.discord.thread_react_channels = tmpseq2
    result.discord.pin_vote_count = d["pin_vote_count"].getInt()

    var db = x["database"]
    result.database = DatabaseConf()
    result.database.host = db["host"].getStr()
    result.database.port = db["port"].getStr()
    result.database.user = db["user"].getStr()
    result.database.password = db["password"].getStr()
    result.database.dbname = db["dbname"].getStr()

    var e = x["email"]
    result.email = EmailConf()
    result.email.verify_domain = e["verify_domain"].getStr()
    result.email.address = e["address"].getStr()
    result.email.port = uint16(e["port"].getInt())
    result.email.ssl = e["ssl"].getBool()
    result.email.user = e["user"].getStr()
    result.email.password = e["password"].getStr()

    var l = x["log"]
    result.log = LogConf()
    result.log.path = l["path"].getStr()

  except CatchableError as e:
    stderr.writeLine("Can't load config")
    stderr.writeLine(e.msg)
    quit(99)

let conf* = initConfig()
