import std/httpclient
import std/osproc
import std/json
import options
import asyncdispatch
import std/strutils

import ../config


proc parse_the_numbers*(numbers: int): Option[string] =
  var browser_out = execCmdEx("python3 " & conf.utils.url_fetch_script & " https://nhentai.net/api/gallery/" & $numbers)
  echo browser_out[0]

  if browser_out[1] != 0:
    return none(string)

  let jsonNode = parseJson(browser_out[0])

  return some(jsonNode["title"]["english"].getStr())


  #var client = newHttpClient()
  #client.headers = newHttpHeaders({ "Content-Type": "application/json" })

  #echo client.getContent("https://nhentai.net/api/gallery/" & $numbers)