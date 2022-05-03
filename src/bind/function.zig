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
        f: [count_args_refs(f)]napi.napi_ref,
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
          defer for (state.f) |ref| if (ref) |x| napi.safe(napi.napi_delete_reference, .{E.raw, x}) catch {};

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
      for (state.f) |*ref| ref.* = null;
      state.A = std.heap.ArenaAllocator.init(A);
      state.a = try args(e, f, ri, .{ .sync = false, .refs = &state.f, .alloc = state.A.allocator() });
      errdefer for (state.f) |ref| if (ref) |x| napi.safe(napi.napi_delete_reference, .{e.raw, x}) catch {};
      try napi.safe(napi.napi_create_async_work, .{e.raw, null, (try e.create(void)).raw, work_wrapper.work, work_wrapper.done, @ptrCast(* align(@alignOf(*State)) anyopaque, state), &w});

      try napi.safe(napi.napi_queue_async_work, .{e.raw, w}); return napi.value.init(p);
    }
  };

  var raw: napi.napi_value = undefined;
  try napi.safe(napi.napi_create_function, .{env.raw, name, name.len, wrapper.callback, null, &raw});

  return napi.value.init(raw);
}



inline fn count_args_refs(comptime f: anytype) comptime_int {
  comptime var refs = 0;
  const I = @typeInfo(@TypeOf(f)).Fn;

  inline for (I.args) |arg| {
    const T = arg.arg_type.?;

    switch (@typeInfo(T)) {
      else => {},

      .Pointer => |info| switch (info.size) {
        else => {},

        .Slice => switch (info.child) {
          else => {},

          u8, i8, u16, i16, u32, i32, f32, u64, i64, f64,
          f16, u24, i24, u40, i40, u48, i48, u56, i56, u128, i128, f128 => refs += 1,
        },
      }
    }
  }

  return refs;
}

inline fn args(env: napi.env, comptime f: anytype, ri: napi.napi_callback_info, options: anytype) !std.meta.ArgsTuple(@TypeOf(f)) {
  const I = @typeInfo(@TypeOf(f)).Fn;
  var a: std.meta.ArgsTuple(@TypeOf(f)) = undefined;

  switch (I.args.len) {
    0 => return a,

    else => {
      var len = I.args.len;
      var napi_args: [I.args.len]napi.napi_value = undefined;
      try napi.safe(napi.napi_get_cb_info, .{env.raw, ri, &len, &napi_args, null, null});

      comptime var refs = 0;
      comptime var envs = 0;
      inline for (I.args) |arg, offset| {
        const T = arg.arg_type.?;
        const raw = napi.value.init(napi_args[offset - envs]);

        // TODO: move out
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

          .Pointer => |info| switch (info.size) {
            // TODO: support c char pointers / opaque type
            else => @compileError("unsupported function parameter type: " ++ @typeName(T)),

            .Slice => switch (info.child) {
              else => @compileError("unsupported function parameter type: " ++ @typeName(T)),

              u8, i8, u16, i16, u32, i32, f32, u64, i64, f64,
              f16, u24, i24, u40, i40, u48, i48, u56, i56, u128, i128, f128 => {
                const TT = info.child;
                var is: bool = undefined;

                const wt = switch (TT) {
                  else => unreachable,
                  f16 => .{ .s = @sizeOf(f16), .e = error.expected_f16_typedarray },
                  f32 => .{ .s = @sizeOf(f32), .e = error.expected_f32_typedarray },
                  f64 => .{ .s = @sizeOf(f64), .e = error.expected_f64_typedarray },
                  f128 => .{ .s = @sizeOf(f128), .e = error.expected_f128_typedarray },
                  u8, i8 => .{ .s = @sizeOf(u8), .e = if (u8 == TT) error.expected_u8_typedarray else error.expected_i8_typedarray },
                  u16, i16 => .{ .s = @sizeOf(u16), .e = if (u16 == TT) error.expected_u16_typedarray else error.expected_i16_typedarray },
                  u24, i24 => .{ .s = @sizeOf(u24), .e = if (u24 == TT) error.expected_u24_typedarray else error.expected_i24_typedarray },
                  u32, i32 => .{ .s = @sizeOf(u32), .e = if (u32 == TT) error.expected_u32_typedarray else error.expected_i32_typedarray },
                  u40, i40 => .{ .s = @sizeOf(u40), .e = if (u40 == TT) error.expected_u40_typedarray else error.expected_i40_typedarray },
                  u48, i48 => .{ .s = @sizeOf(u48), .e = if (u48 == TT) error.expected_u48_typedarray else error.expected_i48_typedarray },
                  u56, i56 => .{ .s = @sizeOf(u56), .e = if (u56 == TT) error.expected_u56_typedarray else error.expected_i56_typedarray },
                  u64, i64 => .{ .s = @sizeOf(u64), .e = if (u64 == TT) error.expected_u64_typedarray else error.expected_i64_typedarray },
                  u128, i128 => .{ .s = @sizeOf(u128), .e = if (u128 == TT) error.expected_u128_typedarray else error.expected_i128_typedarray },
                };

                try napi.safe(napi.napi_is_typedarray, .{env.raw, raw.raw, &is});

                if (!is) {
                  var is_nb: bool = undefined;
                  try napi.safe(napi.napi_is_buffer, .{env.raw, raw.raw, &is_nb});

                  if (!is_nb) return error.expected_buffer_or_typedarray;
              }

                var l: usize = undefined;
                var slice: [*]TT = undefined;
                var t: napi.napi_typedarray_type = undefined;

                switch (is) {
                  true => try napi.safe(napi.napi_get_typedarray_info, .{env.raw, raw.raw, &t, &l, @ptrCast([*]?*anyopaque, &slice), null, null}),
                  else => { t = napi.napi_uint8_array; try napi.safe(napi.napi_get_buffer_info, .{env.raw, raw.raw, @ptrCast([*]?*anyopaque, &slice), &l}); },
                }

                const tt: u8 = switch (t) {
                  else => unreachable,
                  napi.napi_int8_array => @sizeOf(i8),
                  napi.napi_uint8_array => @sizeOf(u8),
                  napi.napi_int16_array => @sizeOf(i16),
                  napi.napi_int32_array => @sizeOf(i32),
                  napi.napi_uint16_array => @sizeOf(u16),
                  napi.napi_uint32_array => @sizeOf(u32),
                  napi.napi_float32_array => @sizeOf(f32),
                  napi.napi_float64_array => @sizeOf(f64),
                  napi.napi_bigint64_array => @sizeOf(i64),
                  napi.napi_biguint64_array => @sizeOf(u64),
                  napi.napi_uint8_clamped_array => @sizeOf(u8),
                };

                if (tt != wt.s and (0 != ((l * tt) % wt.s))) return wt.e;

                a[offset] = slice[0..(l * tt / wt.s)];

                if (@hasField(@TypeOf(options), "refs")) {
                  try napi.safe(napi.napi_create_reference, .{env.raw, raw.raw, 1, &options.refs[refs]}); refs += 1;
                }
              },
            },
          }
        }
      }

      return a;
    },
  }
}