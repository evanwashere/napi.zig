const std = @import("std");
const napi = @import("./src/napi.zig");

const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

fn init(env: napi.env, exports: napi.object) !void {
  try exports.set(env, "sleep", try napi.bind.function(env, sleep, "sleep", allocator));
  try exports.set(env, "sleep_async", try napi.bind.function(env, sleep_async, "sleep", allocator));
}

fn sleep(time: usize) void {
  std.time.sleep(time * std.time.ns_per_ms);
}

fn sleep_async(time: usize) callconv(.Async) void {
  std.time.sleep(time * std.time.ns_per_ms);
}