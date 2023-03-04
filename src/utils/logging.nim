import std/logging

import ../config

let conf = config.conf

var consoleLog* = newConsoleLogger(fmtStr="[$datetime] - $levelname: ")
var fileLog* = newFileLogger(conf.log.path, fmtStr="[$datetime] - $levelname: ", levelThreshold=lvlInfo, bufSize = 0)

addHandler(consoleLog)
addHandler(fileLog)
