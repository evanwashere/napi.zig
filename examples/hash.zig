const std = @import("std");
const napi = @import("./src/napi.zig");

const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

fn init(env: napi.env, exports: napi.object) !void {
  try exports.set(env, "crc32", try napi.bind.function(env, crc32, "crc32", allocator));
  try exports.set(env, "murmur32", try napi.bind.function(env, murmur32, "murmur32", allocator));
  try exports.set(env, "murmur64", try napi.bind.function(env, murmur64, "murmur64", allocator));
}

fn crc32(slice: []u8) callconv(.Async) u32 {
  return std.hash.Crc32.hash(slice);
}

fn murmur32(slice: []u8) callconv(.Async) u32 {
  return std.hash.Murmur2_32.hash(slice);
}

fn murmur64(slice: []u8) callconv(.Async) u64 {
  return std.hash.Murmur2_64.hash(slice);
}