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
    if attach.content_type.get() in ["image/jpeg", "image/png", "image/webp", "image/gif"]:
      try:
        let ext = attach.url.rsplit(".", 1)[1]
        file_path = "/tmp/" & attach.id & ext
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)

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
