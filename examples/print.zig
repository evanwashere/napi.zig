const std = @import("std");
const napi = @import("./src/napi.zig");

const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

fn init(env: napi.env, exports: napi.object) !void {
  try exports.set(env, "print", try napi.bind.function(env, print, "print", allocator));
  try exports.set(env, "print_async", try napi.bind.function(env, print_async, "print_async", allocator));
}

fn print(env: napi.env, string: napi.string) !void {
  const slice = try string.get(env, .utf8, allocator);

  defer allocator.free(slice);
  std.log.info("{s}", .{slice});
}

// async function can't interact with js values so we use serde.string
fn print_async(string: napi.serde.string) callconv(.Async) void {
  std.log.info("{s}", .{string.alloced.slice});
}