import dimscord
#import asyncthreadpool

import stdx/asyncdispatch
import times
import std/strformat
import std/tables
import std/sequtils
import std/strutils
import std/httpclient
import os
import zip/zipfiles
import streams
import std/mimetypes
import json
import std/logging
import options
import std/enumerate
import std/times

import ../config
import ../utils/logging as clogger

let conf = config.conf

proc upload_linx(zip_path, url: string): string =
  var zip_name_seq = zip_path.rsplit('/')
  var zip_name = zip_name_seq[zip_name_seq.len - 1]
  var api_url = url.strip(chars = {'/'}) & "/upload/" & zip_name

  let mimes = newMimetypes()
  var client = newHttpClient(timeout=8000)
  client.headers = newHttpHeaders({ "Linx-Randomize": "yes", "Linx-Expiry": "0" })

  var data = newMultipartData()
  data.addFiles({"uploaded_file": zip_path}, mimeDb = mimes)

  var response: Response
  try:
    response = client.put(api_url, multipart=data)
  except CatchableError:
    return ""
  #echo response.repr
  if response.status == "200 OK":
    return response.bodyStream.readAll()
  else:
    return ""

proc upload_loli(zip_path, url, token: string): string =
  var api_url = url.strip(chars = {'/'}) & "/api/upload/"
  #echo api_url
  let mimes = newMimetypes()
  var client = newHttpClient(timeout=8000)
  var data = newMultipartData()
  data.addFiles({"FileFormName": zip_path}, mimeDb = mimes)

  var response: Response
  try:
    response = client.post(api_url, multipart=data)
  except CatchableError:
    return ""
  #echo response.repr
  if response.status == "200 OK":
    return response.bodyStream.readAll()
  else:
    return ""

proc upload_catbox(zip_path, userhash: string): string =
  let api_url = "https://catbox.moe/user/api.php"

  let mimes = newMimetypes()
  var client = newHttpClient(timeout=8000)
  var data = newMultipartData()
  data["reqtype"] = "fileupload"
  data["userhash"] = userhash
  data.addFiles({"fileToUpload": zip_path}, mimeDb = mimes)

  var response: Response
  try:
    response = client.post(api_url, multipart=data)
  except CatchableError:
    return ""
  if response.status == "200 OK":
    return response.bodyStream.readAll()
  else:
    return ""

proc zip_folder(folderPath: string, zipFilePath: string) =
  var zipFile: ZipArchive
  var file_paths = toSeq(walkDirRec(folderPath))
  #echo file_paths

  discard zipFile.open(zipFilePath, fmWrite)

  for fp in file_paths:
    #echo fp.split('/', 3)
    zipFile.addFile(fp.split('/', 3)[3], newStringStream(readFile(fp)))
    #echo fp.split('/', 3) & " added"

  zipFile.close()
  #echo "zip fin"

proc zip_up(guild_id, room_id: string, msgs: seq[Message], upconf: UploaderConf): string =
  if upconf.site == 0:
    return ""

  var client = newHttpClient()

  var base_dir = "/tmp/" & room_id & $now().utc
  createDir(base_dir)

  for m in msgs:
    var msg_dir = base_dir & "/" & m.id
    createDir(msg_dir)
    if m.content.len > 0:
      let f = open(base_dir & "/" & m.id & "-content.txt", fmWrite)
      f.write(m.content)
      f.close()

    for a in m.attachments:
      client.downloadFile(a.url, msg_dir & "/" & a.filename)

  var zip_path = base_dir & ".zip"
  zip_folder(base_dir, zip_path)
  var url = ""
  if upconf.site == 1:
    url = upload_catbox(zip_path, upconf.catbox_userhash)
  elif upconf.site == 2:
    url = upload_linx(zip_path, upconf.linx_url)
  elif upconf.site == 3:
    url = upload_loli(zip_path, upconf.loli_url, upconf.loli_token)

  try:
    removeDir(base_dir)
    discard tryRemoveFile(zip_path)
  except CatchableError as e:
    error(e.msg)
  return url

proc msgs_to_markdown(channel_name: string, channel_url: string, msgs: seq[Message]): string =
  result &= "# [#" & channel_name & "](" & channel_url & ")\n\n"

  for (i, msg) in enumerate(0, msgs):
    var created_at = msg.timestamp
    result &= "## " & $(i+1) & " " & $msg.author & " — " & created_at & "\n\n"
    result &= "[Odkaz na zprávu](" & channel_url & ")\n\n"
    if msg.content != "":
      result &= "### Text\n\n" & msg.content & "\n\n"
    var files: string
    for f in msg.attachments:
      if f.content_type.isSome and "image" in f.content_type.get():
        files &= "![" & f.filename & "](" & f.url & "); \n"
      else:
        files &= "[" & f.filename & "](" & f.url & "); \n"
    if files != "":
      result &= "### Přílohy\n\n" & files & "\n\n"
    result &= "---\n\n"

proc sum_channel_pins*(discord: DiscordClient, guild_id, room_id: string, pin_cache: TableRef[string, (seq[string], string)], zip: bool, md: bool): Future[(string, string, string)] {.async.} =
  var ch_pins: seq[Message]
  if room_id in pin_cache:
    for mid in pin_cache[room_id][0]:
      ch_pins &= await discord.api.getChannelMessage(room_id, mid)
  else:
    ch_pins = await discord.api.getChannelPins(room_id)
    var tmp: seq[string]
    for m in ch_pins:
      tmp &= m.id
    pin_cache[room_id] = (tmp, "")

  var out_str = "**Shrnutí pinů:**\n"
  var attach_str = "**Soubory:**\n"
  var zip_url = ""
  if zip and pin_cache[room_id][1] == "":
    #zip_url = await spawn zip_up(guild_id, room_id, ch_pins, conf.utils.uploader)
    #zip_url = zip_up(guild_id, room_id, ch_pins, conf.utils.uploader)
    var tmpcf = conf.utils.uploader
    awaitThread(zip_url, guild_id, room_id, ch_pins, tmpcf):
      zip_url = zip_up(guild_id, room_id, ch_pins, tmpcf)
    if zip_url == "" and zip and conf.utils.uploader.site != 0:
      error("Zip upload failed")
    pin_cache[room_id][1] = zip_url
    attach_str &= zip_url
  elif pin_cache[room_id][1] != "":
    zip_url = pin_cache[room_id][1]

  var ch_name: string

  if not md:
    var at_count = 0

    for m in ch_pins:
      out_str &= "*" & m.author.username & "*: "
      if m.content.len > 0:
        out_str &= m.content[0 ..< min(16,m.content.len - 1)] & "..." & '\n'
      else:
        out_str &= '\n'
      out_str &= "https://discord.com/channels/" & guild_id & "/" & room_id & "/" & m.id & '\n' & '\n'

      for a in m.attachments:
        at_count += 1
        attach_str &= a.url & '\n'

    if not zip and at_count > 0:
      out_str &= attach_str
  else:
    ch_name = (await discord.api.getChannel(room_id))[0].get().name
    out_str = msgs_to_markdown(ch_name, "https://discord.com/channels/" & guild_id & "/" & room_id & "/", ch_pins)

  return (out_str, zip_url, ch_name)
