const std = @import("std");
fn path() []const u8 { return @src().file; }

pub usingnamespace @cImport({
  @cDefine("NAPI_VERSION", "8");
  @cInclude(std.fs.path.dirname(path()).? ++ "/node/src/node_api.h");
});