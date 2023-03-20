import std/osproc
import std/json
import options
import std/logging
import asyncdispatch

import ../config
import ../utils/logging as clogger


proc parse_the_numbers*(numbers: int): Future[(Option[JsonNode], Option[string])] {.async.} =
  var browser_out = execCmdEx("python3 " & conf.utils.url_fetch_script & " https://nhentai.net/api/gallery/" & $numbers)

  if browser_out[1] != 0:
    error(browser_out[0])
    return (none JsonNode, none string)

  let jsonWeb = parseJson(browser_out[0])
  var newJson = newJObject()
  var tags: seq[string]
  var title = jsonWeb["title"]
  newJson.add("title", title)
  for i in jsonWeb["tags"]:
    let tagtype = i["type"].getStr()
    let tagname = i["name"].getStr()
    if tagtype == "artist":
      newJson.add("artist", newJString(tagname))
    if tagtype == "language" and tagname != "translated":
      newJson.add("language", newJString(tagname))
    if tagtype == "group":
      newJson.add("group", newJString(tagname))
    if tagtype == "tag":
      tags.add(tagname)

  let jtags = %tags
  newJson.add("tags", jtags)

  var extension = jsonWeb{"images"}{"cover"}{"t"}.getStr()
  if extension == "p":
    extension = ".png"
  else:
    extension = ".jpg"
  let media_id = jsonWeb{"media_id"}.getStr()
  let cover_url = "https://t3.nhentai.net/galleries/" & media_id & "/cover" & extension
  return (some newJson, some cover_url)

#[
  randomize()
  let chars = {'a'..'z','A'..'Z'}
  var coverfile = newString(12)
  for i in 0..<12:
    coverfile[i] = sample(chars)

  let cover_path = "/tmp/" & coverfile & extension
  try:
    var client = newHttpClient()
    client.downloadFile(cover_url, cover_path)

    return (some newJson, some cover_path)

  except CatchableError as e:
    error(e.msg)
    return (some newJson, none string)
]#
