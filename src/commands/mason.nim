import std/httpclient

proc parse_the_numbers*(numbers: int) =
  var client = newHttpClient()
  client.headers = newHttpHeaders({ "Content-Type": "application/json" })

  echo client.getContent("https://nhentai.net/api/gallery/" & $numbers)