from dimscord import Attachment, Embed, EmbedImage, EmbedVideo
import dhash
import asynctools

import options
import std/asyncdispatch
import std/logging
import std/strformat
import std/strutils
import std/httpclient

import ../db/queries
import ../utils/logging as clogger

# commiting crimes against humanity because I can't be bothered to rewrite dedupe_media to support embeds
proc embed_to_attachment*(embed: Embed): Option[Attachment] =
  if embed.type.get() == "image":
    var url = embed.url.get()
    var id = url.rsplit("/", 1)[1].split(".", 1)[0]
    var file_ext = url.rsplit(".", 1)[1].split("?", 1)[0]
    var content_type: string
    if file_ext == "png":
      content_type = "image/png"
    elif file_ext == "jpg" or file_ext == "jpeg":
      content_type = "image/jpeg"
    elif file_ext == "gif":
      content_type = "image/gif"
    elif file_ext == "webp":
      content_type = "image/webp"
    else:
      return none(Attachment)
    return some(Attachment(id: id, url: url, content_type: some content_type))
  elif embed.type.get() == "video" or embed.type.get() == "gifv":
    var url: string
    if embed.type.get() == "gifv":
      url = embed.video.get().url.get()
    else:
      url = embed.url.get()
    var id = url.rsplit("/", 1)[1].split(".", 1)[0]
    var file_ext = url.rsplit(".", 1)[1].split("?", 1)[0]
    var content_type: string
    if file_ext == "mp4":
      content_type = "video/mp4"
    elif file_ext == "ogg":
      content_type = "video/ogg"
    elif file_ext == "webm":
      content_type = "video/webm"
    else:
      return none(Attachment)
    return some(Attachment(id: id, url: url, content_type: some content_type))
  return none(Attachment)

proc process_media_file(file_path: string, attach: Attachment): Future[string] {.async.} =
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
    raise newException(CatchableError, "Failed to process media file")

  return "/tmp/" & attach.id & ".png"

proc dedupe_media*(guild_id, channel_id, message_id: string, attach: Attachment): Future[(bool, int, string)] {.async.} =
  var file_path: string

  if attach.content_type.isSome:
    var client = newAsyncHttpClient()
    let ext = attach.url.rsplit(".", 1)[1].split("?")[0]
    file_path = "/tmp/" & attach.id & "." & ext
    if attach.content_type.get() in ["image/jpeg", "image/png"]:
      try:
        await client.downloadFile(attach.url, file_path)

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
    if attach.content_type.get() in ["video/mp4", "video/ogg", "video/webm", "image/gif", "image/webp"]:
      try:
        await client.downloadFile(attach.url, file_path)

        file_path = await process_media_file(file_path, attach)

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
  else:
    return (false, 0, "")

  let grays = get_grays(file_path, 16, 16)
  let query_res = get_media_distance(guild_id, channel_id, grays)

  discard insert_media(guild_id, channel_id, message_id, attach.id, grays)

  if query_res.isNone:
    return (false, 0, "")


  var duplicate_med = query_res.get()[0] & "|" & query_res.get()[1]

  let distance = parseFloat(query_res.get()[2])

  # 800 is randomly selected, but in my testing should be about 25% difference
  if distance < 800:
    return (true, int((1 - distance / 3200) * 100), duplicate_med)
  return (false, 0, "")
