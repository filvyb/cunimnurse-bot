import std/logging

import config

let conf = config.conf

var consoleLog* = newConsoleLogger(fmtStr="[$datetime] - $levelname: ")
var rollingLog* = newRollingFileLogger(conf.log.path, fmtStr="[$datetime] - $levelname: ")

addHandler(consoleLog)
addHandler(rollingLog)
