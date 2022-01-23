const std = @import("std");
const napi = @import("./src/napi.zig");

const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

fn init(env: napi.env, exports: napi.object) !void {
  try exports.set(env, "encode", try napi.bind.function(env, encode, "encode", allocator));
  try exports.set(env, "decode", try napi.bind.function(env, decode, "decode", allocator));
}

fn encode(env: napi.env, string: napi.string) !napi.string {
  const slice = try string.get(env, .utf8, allocator);

  defer allocator.free(slice);
  const encoder = std.base64.standard.Encoder;
  const encoded = try allocator.alloc(u8, encoder.calcSize(slice.len));

  defer allocator.free(encoded);
  _ = encoder.encode(encoded, slice);
  return napi.string.new(env, .latin1, encoded);
}

fn decode(env: napi.env, string: napi.string) !napi.string {
  const slice = try string.get(env, .utf8, allocator);

  defer allocator.free(slice);
  const decoder = std.base64.standard.Decoder;
  const decoded = try allocator.alloc(u8, try decoder.calcSizeForSlice(slice));

  defer allocator.free(decoded);
  try decoder.decode(decoded, slice);
  return napi.string.new(env, .latin1, decoded);
}