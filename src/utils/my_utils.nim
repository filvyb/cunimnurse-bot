from dimscord import Attachment
import imageman
import dhash
import bigints

import std/httpclient
import std/base64
import std/asyncdispatch
import std/logging
import std/strformat
import std/tables
import std/sets
import std/strutils
import std/osproc
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
    if attach.content_type.get() in ["image/jpeg", "image/png", "image/webp"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
    if attach.content_type.get() in ["video/mp4", "video/ogg", "video/webm", "image/gif"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)


        var ffmpeg_out = execCmdEx(fmt"ffmpeg -i {file_path} -vf 'blackdetect=d=0.05:pix_th=0.67' -an -f null - 2>&1 | grep blackdetect")

        var cut_time = ""

        if ffmpeg_out[1] == 0:
          var ffmpeg_out_split = ffmpeg_out[0].split({'\n', '\r'})
          
          if ffmpeg_out_split.len != 1:
            var start_time = ffmpeg_out_split[1].splitWhitespace()[3].split({':'})[1]
            if start_time == "0":
              cut_time &= "-ss "
              cut_time &= ffmpeg_out_split[1].splitWhitespace()[4].split({':'})[1] & " "

        var ffmpeg_thumb_out = execCmdEx(fmt"ffmpeg -i {file_path} {cut_time}-frames:v 1 /tmp/{attach.id}.png -y")

        if ffmpeg_thumb_out[1] != 0:
          return (false, 0, "")

        file_path = "/tmp/" & attach.id & ".png"

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
  else:
    return (false, 0, "")

  let hash = dhash_int(get_img(file_path), 10)
  discard insert_media(guild_id, channel_id, message_id, attach.id, toString(hash, 16))
  let channel_media = get_all_channel_media(guild_id, channel_id)

  var hamming_min = 128
  var duplicate_med = ""
  for med in channel_media.get():
    if attach.id == med[1]:
      continue
    var hamming = get_num_bits_different(hash, initBigInt(med[2], 16))
    if hamming < hamming_min:
      duplicate_med = med[0] & "|" & med[1]
      hamming_min = hamming

  if hamming_min <= 14:
    return (true, int((1 - hamming_min / 128) * 100), duplicate_med)
  return (false, 0, "")
