import std/httpclient
import std/base64
import std/asyncdispatch
import std/logging
import std/strformat

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