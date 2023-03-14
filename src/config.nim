import parsetoml

import std/os
import std/unicode

type
  DiscordConf* = object of RootObj
    token*: string
    verify_channel*: string
    reaction_channels*: seq[string]
    thread_react_channels*: seq[string]
    dedupe_channels*: seq[string]
    confession_channel*: string
    verified_role*: string
    moderator_role*: string
    admin_role*: string
    helper_role*: string
    teacher_role*: string
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
  UtilsConf* = object of RootObj
    mason*: bool
    url_fetch_script*: string
  Config* = object of RootObj
    discord*: DiscordConf
    database*: DatabaseConf
    email*: EmailConf
    log*: LogConf
    utils*: UtilsConf


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
    result.discord.verify_channel = d["verify_channel"].getStr()
    result.discord.confession_channel = d["confession_channel"].getStr()
    result.discord.verified_role = d["verified_role"].getStr().toLower()
    result.discord.moderator_role = d["moderator_role"].getStr().toLower()
    result.discord.helper_role = d["helper_role"].getStr().toLower()
    result.discord.admin_role = d["admin_role"].getStr().toLower()
    result.discord.teacher_role = d["teacher_role"].getStr().toLower()
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
    var tmp3 = d["dedupe_channels"].getElems()
    var tmpseq3: seq[string]
    for x in tmp3:
      tmpseq3.add(x.getStr())
    result.discord.dedupe_channels = tmpseq3
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

    var u = x["utils"]
    result.utils = UtilsConf()
    result.utils.mason = u["mason"].getBool()
    result.utils.url_fetch_script = u["url_fetch_script"].getStr()

  except CatchableError as e:
    stderr.writeLine("Can't load config")
    stderr.writeLine(e.msg)
    quit(99)

let conf* = initConfig()
