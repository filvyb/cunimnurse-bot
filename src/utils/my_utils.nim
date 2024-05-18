from dimscord import Attachment
import imageman
import dhash
import asynctools

import std/httpclient
import std/base64
import std/asyncdispatch
import std/logging
import std/strformat
import std/tables
import std/sets
import std/strutils
import options

import ../db/queries
import ../utils/logging as clogger

proc download_emoji*(emoji_id: string, animated = false): Future[string] {.async.} =
  var ext = ".png"
  if animated:
    ext = ".gif"
  let emoji_link = fmt"https://cdn.discordapp.com/emojis/{emoji_id}{ext}"
  let file_path = "/tmp/" & emoji_id & ext

  try:
    var client = newAsyncHttpClient()
    await client.downloadFile(emoji_link, file_path)

    var file = readFile(file_path)
    let ret = encode(file, false)

    return ret

  except CatchableError as e:
    error(e.msg)
    return ""

proc tableDiff*[A, B](table1, table2: Table[A, B]): Table[A, B] =
  var diffTable = initTable[A, B]()
  for key1, value1 in table1:
    if not contains(table2, key1):
      diffTable[key1] = value1

  return diffTable

proc `-`*[A, B](table1, table2: Table[A, B]): Table[A, B] {.inline.} =
  return tableDiff(table1, table2)

proc `+`*[A, B](table1, table2: Table[A, B]): Table[A, B] {.inline.} =
  return merge(table1, table2)

proc dedupe_media*(guild_id, channel_id, message_id: string, attach: Attachment): Future[(bool, int, string)] {.async.} =
  var file_path: string

  if attach.content_type.isSome:
    let ext = attach.url.rsplit(".", 1)[1]
    file_path = "/tmp/" & attach.id & "." & ext
    if attach.content_type.get() in ["image/jpeg", "image/png"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
    if attach.content_type.get() in ["video/mp4", "video/ogg", "video/webm", "image/gif", "image/webp"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)


        var ffmpeg_out_tmp = await execProcess(fmt"ffmpeg -i {file_path} -vf 'blackdetect=d=0.05:pix_th=0.67' -an -f null - 2>&1 | grep blackdetect")
        var ffmpeg_out = (ffmpeg_out_tmp.output, ffmpeg_out_tmp.exitcode)

        var cut_time = ""

        if ffmpeg_out[1] == 0:
          var ffmpeg_out_split = ffmpeg_out[0].split({'\n', '\r'})
          
          if ffmpeg_out_split.len != 1:
            var start_time = ffmpeg_out_split[1].splitWhitespace()[3].split({':'})[1]
            if start_time == "0":
              cut_time &= "-ss "
              cut_time &= ffmpeg_out_split[1].splitWhitespace()[4].split({':'})[1] & " "

        var ffmpeg_thumb_out_tmp = await execProcess(fmt"ffmpeg -i {file_path} {cut_time}-frames:v 1 /tmp/{attach.id}.png -y")
        var ffmpeg_thumb_out = (ffmpeg_thumb_out_tmp.output, ffmpeg_thumb_out_tmp.exitcode)

        if ffmpeg_thumb_out[1] != 0:
          return (false, 0, "")

        file_path = "/tmp/" & attach.id & ".png"

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
  else:
    return (false, 0, "")

  let grays = get_grays(file_path, 16, 16)
  let query_res = await get_media_distance(guild_id, channel_id, grays)

  discard await insert_media(guild_id, channel_id, message_id, attach.id, grays)

  if query_res.isNone:
    return (false, 0, "")


  var duplicate_med = query_res.get()[0] & "|" & query_res.get()[1]

  let distance = parseFloat(query_res.get()[2])

  # 800 is randomly selected, but in my testing should be about 25% difference
  if distance < 800:
    return (true, int((1 - distance / 3200) * 100), duplicate_med)
  return (false, 0, "")

proc convert_md2pdf*(md: string): Future[string] {.async.} =
  var md_path = "/tmp/pins.md"
  var out_path = "/tmp/pins.pdf"
  try:
    writeFile(md_path, md)
  except IOError as e:
    error(e.msg & "\n" & "e.trace")
    return ""

  var cmd = "pandoc " & md_path & " -V colorlinks=true -V linkcolor=blue -V geometry:margin=0.4in -o " & out_path
  var pandoc_out = await execProcess(cmd)
  if pandoc_out.exitcode != 0:
    error("Pandoc failed: " & pandoc_out.output)
  else:
    result = out_path

proc extractBetween*(text: string, tbegin: string, tend: string, pos = 0): string =
  try:
    var start_pos = text.find(tbegin, pos) + tbegin.len
    var end_pos = text.find(tend, start_pos)
    result = text[start_pos ..< end_pos]
  except:
    result = ""
