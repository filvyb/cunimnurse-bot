import std/db_postgres
import std/strformat

import config

when is_main_module:
  var conf = config.initConfig()
  
  let conn = open("", conf.database.user, conf.database.password, fmt"host={conf.database.host} port={conf.database.port} dbname={conf.database.dbname}")
  