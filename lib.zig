const std = @import("std");
const print = std.debug.print;
const napi = @import("./src/napi.zig");
const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

comptime {
  const n = @import("./src/napi/c-napi/types.zig");

  std.testing.refAllDecls(n);
}

fn init(env: napi.env, exports: napi.object) !void {
  _ = env;
  _ = exports;
  const n = @import("./src/napi/c-napi/types.zig");

  const heap_string = try allocator.alloc(u8, 64);

  std.mem.set(u8, heap_string, 'a');

  const nenv = n.Env.init(env.raw);
  const np = try n.Promise.init(nenv);

  const nv = try n.Function.init(nenv, "hello", (opaque {
    pub fn hello(envv: n.Env, info: n.CallbackInfo) !n.Value {
      _ = info;
      _ = envv;
      return error.aaaa;
      // return n.Value.from(try n.String.init(envv, .utf8, "hello"));
    }
  }).hello);

  try exports.set(env, "zig", napi.value.init(np.inner));

  try np.resolve(nenv, nv);

  // std.log.info("{}", .{std.mem.eql(u16, ss, sss)});

  // std.log.info("{}", .{try nv.len(nenv)});

  // const b: ?u1 = null;
  // const o = try napi.object.new(env);
  // const a = try napi.array.new(env, 5);

  // const heap_string_utf16 = try allocator.alloc(u16, 100);

  // defer allocator.free(heap_string);
  // defer allocator.free(heap_string_utf16);

  {
    // try exports.set(env, "zig", try env.create(a));
    // try exports.set(env, "zig", try env.create(o));
    // try exports.set(env, "zig", try env.create(b));
    // try exports.set(env, "zig", try env.create(true));
    // try exports.set(env, "zig", try env.create(null));
    // try exports.set(env, "zig", try env.create(void));
    // try exports.set(env, "zig", try env.create(error.abcdef));
    // try exports.set(env, "zig", try env.create(@as(i128, -1)));
    // try exports.set(env, "zig", try env.create(enum { a, b, c }));
    // try exports.set(env, "zig", try env.create(enum { a, b, c }.a));
    // try exports.set(env, "zig", try env.create(.{ .a = 1, .b = 2, .c = .{3} }));
    // try exports.set(env, "zig", try env.create(@bitCast(u53, @as(i53, -1)))); // int
    // try exports.set(env, "zig", try env.create(@bitCast(u54, @as(i54, -1)))); // bigint
    // try exports.set(env, "zig", try env.create(try napi.string.new(env, .utf8, "hello")));
    // try exports.set(env, "zig", try env.create(try napi.string.new(env, .latin1, "hello".*)));
    // try exports.set(env, "zig", try env.create(union(enum) { a: u2, b: u2, c: u2 }{ .a = 1 }));
    // try exports.set(env, "zig", try env.create(try napi.string.new(env, .latin1, heap_string)));
    // try exports.set(env, "zig", try env.create(try napi.string.new(env, .utf16, heap_string_utf16)));
  }

  // try exports.set(env, "zig", try napi.bind.function(env, sleep, "sleep", allocator));
  // try exports.set(env, "zig", try napi.bind.function(env, random, "random", allocator));
}

// fn sleep(time: usize) !void {
//   std.time.sleep(time * std.time.ns_per_ms);

//   return error.aaa;
// }

// fn random(slice: []u8, slice2: []u8) u32 {
//   _ = slice2;
//   std.time.sleep(1 * std.time.ns_per_s);

//   return @intCast(u32, slice.len);
// }