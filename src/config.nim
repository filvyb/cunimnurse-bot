import parsetoml

import std/os
import std/unicode
import std/sets

type
  UploaderConf* = object of RootObj
    site*: int
    catbox_userhash*: string
    linx_url*: string
    loli_url*: string
    loli_token*: string
  DiscordConf* = object of RootObj
    token*: string
    verify_channel*: string
    reaction_channels*: HashSet[string]
    thread_react_channels*: HashSet[string]
    dedupe_channels*: HashSet[string]
    cultured_channels*: HashSet[string]
    admin_channel*: string
    confession_channel*: string
    pin_sum_channel*: string
    pin_categories2sum*: HashSet[string]
    verified_role*: string
    moderator_role*: string
    admin_role*: string
    helper_role*: string
    teacher_role*: string
    bachelors_role_suffix*: string
    masters_role_suffix*: string
    pin_vote_count*: int
  DatabaseConf* = object of RootObj
    host*: string
    port*: string
    user*: string
    password*: string
    dbname*: string
  EmailConf* = object of RootObj
    use_mail*: bool
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
    openweather_token*: string
    md2pdf*: bool
    uploader*: UploaderConf
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
    result.discord.pin_sum_channel = d["pin_sum_channel"].getStr()
    result.discord.verified_role = d["verified_role"].getStr().toLower()
    result.discord.moderator_role = d["moderator_role"].getStr().toLower()
    result.discord.helper_role = d["helper_role"].getStr().toLower()
    result.discord.admin_role = d["admin_role"].getStr().toLower()
    result.discord.teacher_role = d["teacher_role"].getStr().toLower()
    result.discord.bachelors_role_suffix = d["bachelors_role_suffix"].getStr().toLower()
    result.discord.masters_role_suffix = d["masters_role_suffix"].getStr().toLower()
    var tmp = d["reaction_channels"].getElems()
    var tmpseq: seq[string]
    for t in tmp:
      tmpseq.add(t.getStr())
    result.discord.reaction_channels = toHashSet(tmpseq)
    var tmp2 = d["thread_react_channels"].getElems()
    var tmpseq2: seq[string]
    for t in tmp2:
      tmpseq2.add(t.getStr())
    result.discord.thread_react_channels = toHashSet(tmpseq2)
    var tmp3 = d["dedupe_channels"].getElems()
    var tmpseq3: seq[string]
    for t in tmp3:
      tmpseq3.add(t.getStr())
    result.discord.dedupe_channels = toHashSet(tmpseq3)
    var tmp4 = d["pin_categories2sum"].getElems()
    var tmpseq4: seq[string]
    for t in tmp4:
      tmpseq4.add(t.getStr())
    result.discord.pin_categories2sum = toHashSet(tmpseq4)
    var tmp5 = d["cultured_channels"].getElems()
    var tmpseq5: seq[string]
    for t in tmp5:
      tmpseq5.add(t.getStr())
    result.discord.cultured_channels = toHashSet(tmpseq5)
    result.discord.admin_channel = d["admin_channel"].getStr()
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
    result.email.use_mail = e["use_mail"].getBool()
    if result.email.use_mail:
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
    result.utils.md2pdf = u["md2pdf"].getBool()
    result.utils.openweather_token = u["openweather_token"].getStr()

    var uu = u["uploader"]
    result.utils.uploader = UploaderConf()
    result.utils.uploader.site = uu["site"].getInt()
    if result.utils.uploader.site == 1:
      result.utils.uploader.catbox_userhash = uu["catbox_hash"].getStr()
    elif result.utils.uploader.site == 2:
      result.utils.uploader.linx_url = uu["linx_url"].getStr()
    elif result.utils.uploader.site == 3:
      result.utils.uploader.loli_url = uu["loli_url"].getStr()
      result.utils.uploader.loli_token = uu["loli_token"].getStr()

  except CatchableError as e:
    stderr.writeLine("Can't load config")
    stderr.writeLine(e.msg)
    quit(99)

let conf* = initConfig()
