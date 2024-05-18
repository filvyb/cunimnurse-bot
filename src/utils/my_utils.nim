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

proc extractBetween*(text, tbegin, tend: string, pos = 0): string =
  try:
    var start_pos = text.find(tbegin, pos) + tbegin.len
    var end_pos = text.find(tend, start_pos)
    result = text[start_pos ..< end_pos]
  except:
    result = ""
