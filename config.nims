# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

when findExe("mold").len > 0 and defined(linux):
  switch("passL", "-fuse-ld=mold")
