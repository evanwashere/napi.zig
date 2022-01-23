const std = @import("std");
const napi = @import("../napi.zig");
const serde = @import("../serde.zig");

pub fn bind(env: napi.env, comptime f: anytype, comptime name: [:0]const u8, comptime A: std.mem.Allocator) !napi.value {
  const T = @TypeOf(f);
  const I = @typeInfo(T);

  switch (I) {
    else => @compileError("expected function, got " + @typeName(T)),

    .Fn => |info| switch (info.calling_convention) {
      else => return bind_sync(env, f, name),
      .Async => return bind_async(env, f, name, A),
    },
  }
}

fn bind_sync(env: napi.env, comptime f: anytype, comptime name: [:0]const u8) !napi.value {
  const info = @typeInfo(@TypeOf(f)).Fn;

  const wrapper = opaque {
    pub fn callback(re: napi.napi_env, ri: napi.napi_callback_info) callconv(.C) napi.napi_value {
      if (zig(napi.env.init(re), ri)) |x| { return x.raw; }
      else |err| napi.env.init(re).throw_error(@errorName(err)) catch {};

      return null;
    }

    pub fn zig(e: napi.env, ri: napi.napi_callback_info) !napi.value {
      const a = try args(e, f, ri, .{ .sync = true });

      switch (@typeInfo(info.return_type.?)) {
        else => return try e.create(@call(.{ .modifier = .no_async }, f, a)),
        .ErrorUnion => return try e.create(try @call(.{ .modifier = .no_async }, f, a)),
      }
    }
  };

  var raw: napi.napi_value = undefined;
  try napi.safe(napi.napi_create_function, .{env.raw, name, name.len, wrapper.callback, null, &raw});

  return napi.value.init(raw);
}

fn bind_async(env: napi.env, comptime f: anytype, comptime name: [:0]const u8, comptime A: std.mem.Allocator) !napi.value {
  const info = @typeInfo(@TypeOf(f)).Fn;
  const has_error = .ErrorUnion == @typeInfo(info.return_type.?);

  const wrapper = opaque {
    pub fn callback(re: napi.napi_env, ri: napi.napi_callback_info) callconv(.C) napi.napi_value {
      if (zig(napi.env.init(re), ri)) |x| { return x.raw; }
      else |err| napi.env.init(re).throw_error(@errorName(err)) catch {};

      return null;
    }

    pub fn zig(e: napi.env, ri: napi.napi_callback_info) !napi.value {
      var p: napi.napi_value = undefined;
      var d: napi.napi_deferred = undefined;
      var w: napi.napi_async_work = undefined;
      try napi.safe(napi.napi_create_promise, .{e.raw, &d, &p});

      const State = struct {
        d: napi.napi_deferred,
        r: info.return_type.?,
        A: std.heap.ArenaAllocator,
        e: if (has_error) bool else void,
        a: std.meta.ArgsTuple(@TypeOf(f)),
      };

      const work_wrapper = opaque {
        pub fn work(_: napi.napi_env, rs: ?*anyopaque) callconv(.C) void {
          const state = @ptrCast(*State, @alignCast(@alignOf(*State), rs));

          // fixes env.raw from previous env
          // DISABLED: only serde types supported
          // inline for (info.args) |arg, offset| {
          //   const T = arg.arg_type.?;

          //   switch (@typeInfo(T)) {
          //     else => {},
          //     .Struct => switch (T) {
          //       else => {},
          //       napi.env => state.a[offset].raw = re,
          //     },
          //   }
          // }

          nosuspend call(state);
        }

        pub fn call(state: *State) void {
          var stack: [@sizeOf(@Frame(f))]u8 align(@alignOf(@Frame(f))) = undefined;

          // TODO: replace x with &state.r (https://github.com/ziglang/zig/issues/7966)
          if (!has_error) {
            var x: info.return_type.? = undefined;
            _ = await @asyncCall(&stack, &x, f, state.a);

            state.r = x;
          }

          else {
            var x: info.return_type.? = undefined;
            if (await @asyncCall(&stack, &x, f, state.a))

            |ok| {
              state.r = ok;
              state.e = false;
            } else |err| {
              state.r = err;
              state.e = true;
            }
          }
        }

        pub fn done(re: napi.napi_env, _: napi.napi_status, rs: ?*anyopaque) callconv(.C) void {
          const E = napi.env.init(re);
          const state = @ptrCast(*State, @alignCast(@alignOf(*State), rs));

          defer A.destroy(state);
          defer state.A.deinit();
          const r = E.create(state.r) catch |err| {
            return napi.safe(napi.napi_reject_deferred, .{E.raw, state.d, (E.create(err) catch unreachable).raw}) catch {};
          };

          switch (has_error) {
            false => napi.safe(napi.napi_resolve_deferred, .{E.raw, state.d, r.raw}) catch {},

            true => switch (state.e) {
              true => napi.safe(napi.napi_reject_deferred, .{E.raw, state.d, r.raw}) catch {},
              false => napi.safe(napi.napi_resolve_deferred, .{E.raw, state.d, r.raw}) catch {},
            },
          }
        }
      };

      const state = try A.create(State);

      state.d = d;
      errdefer A.destroy(state);
      errdefer state.A.deinit();
      state.A = std.heap.ArenaAllocator.init(A);
      state.a = try args(e, f, ri, .{ .sync = false, .alloc = state.A.allocator() });
      try napi.safe(napi.napi_create_async_work, .{e.raw, null, (try e.create(void)).raw, work_wrapper.work, work_wrapper.done, @ptrCast(* align(@alignOf(*State)) anyopaque, state), &w});

      try napi.safe(napi.napi_queue_async_work, .{e.raw, w}); return napi.value.init(p);
    }
  };

  var raw: napi.napi_value = undefined;
  try napi.safe(napi.napi_create_function, .{env.raw, name, name.len, wrapper.callback, null, &raw});

  return napi.value.init(raw);
}

inline fn args(env: napi.env, comptime f: anytype, ri: napi.napi_callback_info, options: anytype) !std.meta.ArgsTuple(@TypeOf(f)) {
  const info = @typeInfo(@TypeOf(f)).Fn;
  var a: std.meta.ArgsTuple(@TypeOf(f)) = undefined;

  switch (info.args.len) {
    0 => return a,

    else => {
      var len = info.args.len;
      var napi_args: [info.args.len]napi.napi_value = undefined;
      try napi.safe(napi.napi_get_cb_info, .{env.raw, ri, &len, &napi_args, null, null});

      comptime var envs = 0;
      inline for (info.args) |arg, offset| {
        const T = arg.arg_type.?;
        const raw = napi.value.init(napi_args[offset - envs]);

        switch (@typeInfo(T)) {
          .Bool => a[offset] = try serde.types.@"bool".deserialize(env, raw),
          .Int, .Float => a[offset] = try serde.types.@"number".deserialize(env, T, raw),
          else => @compileError("unsupported function parameter type: " ++ @typeName(T)),

          .Union => switch (T) {
            else => @compileError("unsupported function parameter type: " ++ @typeName(T)),
            napi.serde.string => if (true == options.sync)
              @compileError("serde.string is not allowed in sync function (use napi.string)")
              else { a[offset] = try serde.types.@"string".deserialize(env, raw, options.alloc); }
          },

          .Struct => switch (T) {
            else => @compileError("unsupported function parameter type: " ++ @typeName(T)),
            napi.value => if (true == options.sync) { a[offset] = raw; } else @compileError("napi.value is not allowed in async function"),
            napi.env => if (true == options.sync) { envs += 1; a[offset] = env; } else @compileError("napi.env is not allowed in async function"),

            napi.object => if (true == options.sync) switch (try raw.typeof(env)) {
              else => return napi.expected.expected_object,
              .js_object => a[offset] = napi.object.init(raw.raw),
            } else @compileError("napi.object is not allowed in async function"),

            napi.string => if (true == options.sync) switch (try raw.typeof(env)) {
              else => return napi.expected.expected_string,
              .js_string => a[offset] = napi.string.init(raw.raw),
            } else @compileError("napi.string is not allowed in async function (use serde.string)"),

            napi.array => if (true == options.sync) {
              var b: bool = undefined;
              try napi.safe(napi.napi_is_array, .{env.raw, raw.raw, &b});

              switch (b) {
                else => return napi.expected.expected_array,
                true => a[offset] = napi.array.init(raw.raw),
              }
            } else @compileError("napi.array is not allowed in async function"),
          },
        }
      }

      return a;
    },
  }
}