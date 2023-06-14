import dimscord
import asyncthreadpool

import asyncdispatch
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

import ../config
import ../utils/logging as clogger

let conf = config.conf

proc upload_catbox(zip_path, userhash: string): string =
  let api_url = "https://catbox.moe/user/api.php"

  let mimes = newMimetypes()
  var client = newHttpClient()
  var data = newMultipartData()
  data["reqtype"] = "fileupload"
  data["userhash"] = userhash
  data.addFiles({"fileToUpload": zip_path}, mimeDb = mimes)

  let response = client.post(api_url, multipart=data)
  if response.status == "200":
    return response.body
  else:
    error("Upload to Catbox failed")
    return ""

proc zip_folder(folderPath: string, zipFilePath: string) =
  var zipFile: ZipArchive
  var file_paths = toSeq(walkDirRec(folderPath))
  #echo file_paths

  discard zipFile.open(zipFilePath, fmWrite)

  for fp in file_paths:
    #echo fp.split('/', 3)
    zipFile.addFile(fp.split('/', 3)[3], newStringStream(readFile(fp)))

  zipFile.close()

proc zip_up(guild_id, room_id: string, msgs: seq[Message], userhash: string): string =
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
  var url = upload_catbox(zip_path, userhash)
  removeDir(base_dir)
  discard tryRemoveFile(zip_path)
  return url


proc sum_channel_pins*(discord: DiscordClient, guild_id, room_id: string, pin_cache: TableRef[string, (seq[string], string)], zip: bool): Future[(string, string)] {.async.} =
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
    zip_url = await spawn zip_up(guild_id, room_id, ch_pins, conf.utils.catbox_userhash)
    pin_cache[room_id][1] = zip_url
    attach_str &= zip_url

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

  return (out_str, zip_url)
