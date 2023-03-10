import std/httpclient
import std/base64
import std/asyncdispatch
import std/logging
import std/strformat
import std/tables
import std/sets

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
