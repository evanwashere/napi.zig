const std = @import("std");
const A = std.heap.c_allocator;
const c = @import("../headers/c.zig");
const call = @import("./safe.zig").call;

pub const Env = struct {
  inner: c.napi_env,

  pub fn init(env: c.napi_env) Env {
    return Env { .inner = env };
  }

  pub fn throw_error(self: Env, name: [:0]const u8) !void {
    try call(c.napi_throw_error, .{self.inner, null, name});
  }

  pub fn throw(self: Env, err: anytype) !void {
    try call(c.napi_throw, .{self.inner, Value.from(err).inner});
  }

  pub fn seal(self: Env, value: anytype) !void {
    try call(c.napi_object_seal, .{self.inner, Value.from(value).inner});
  }

  pub fn freeze(self: Env, value: anytype) !void {
    try call(c.napi_object_freeze, .{self.inner, Value.from(value).inner});
  }
};

const Ref = struct {};
const Wrapped = struct {};
const External = struct {};
const AsyncWork = struct {};

pub const CallbackInfo = struct {
  inner: c.napi_callback_info,
};

pub const Value = struct {
  inner: c.napi_value,

  pub fn from(value: anytype) Value {
    const T = @TypeOf(value);

    return switch (T) {
      c.napi_value => Value { .inner = value },
      else => @compileError("expected napi type, got: " ++ @typeName(T)),
      Null, Date, Value, Array, Error, Object, String, Number, Buffer, BigInt, Promise, Boolean, Function, Undefined, TypedArray, ArrayBuffer => Value { .inner = value.inner },
    };
  }
};

pub const Null = struct {
  inner: c.napi_value,

  pub fn init(env: Env) !Null {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_null, .{env.inner, &raw});

    return Null { .inner = raw };
  }
};

pub const Undefined = struct {
  inner: c.napi_value,

  pub fn init(env: Env) !Undefined {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_undefined, .{env.inner, &raw});

    return Undefined { .inner = raw };
  }
};

pub const Error = struct {
  inner: c.napi_value,

  pub fn init(env: Env, code: ?String, value: String) !Error {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_error, .{env.inner, if (code) |x| x.inner else null, value.inner, &raw});

    return Error { .inner = raw };
  }
};

pub const Boolean = struct {
  inner: c.napi_value,

  pub fn init(env: Env, value: bool) !Boolean {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_boolean, .{env.inner, value, &raw});

    return Boolean { .inner = raw };
  }

  pub fn get(self: Boolean, env: Env) !bool {
    var value: bool = undefined;
    try call(c.napi_get_value_bool, .{env.inner, self.inner, &value});

    return value;
  }
};

pub const Date = struct {
  inner: c.napi_value,

  pub fn init(env: Env, value: i64) !Date {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_date, .{env.inner, @intToFloat(f64, value), &raw});

    return Date { .inner = raw };
  }

  pub fn get(self: Date, env: Env) !i64 {
    var value: f64 = undefined;
    try call(c.napi_get_date_value, .{env.inner, self.inner, &value});

    return @floatToInt(i64, value);
  }
};

pub const Promise = struct {
  inner: c.napi_value,
  deferred: c.napi_deferred,

  pub fn init(env: Env) !Promise {
    var raw: c.napi_value = undefined;
    var deferred: c.napi_deferred = undefined;
    try call(c.napi_create_promise, .{env.inner, &deferred, &raw});

    return Promise { .inner = raw, .deferred = deferred };
  }

  // TODO: add serde support?
  pub fn reject(self: Promise, env: Env, value: anytype) !void {
    try call(c.napi_reject_deferred, .{env.inner, self.deferred, Value.from(value).inner});
  }

  // TODO: add serde support?
  pub fn resolve(self: Promise, env: Env, value: anytype) !void {
    try call(c.napi_resolve_deferred, .{env.inner, self.deferred, Value.from(value).inner});
  }
};

pub const Array = struct {
  inner: c.napi_value,

  pub fn len(self: Array, env: Env) !u32 {
    var length: u32 = undefined;
    try call(c.napi_get_array_length, .{env.inner, self.inner, &length});

    return length;
  }

  pub fn set(self: Array, env: Env, index: u32, value: anytype) !void {
    try call(c.napi_set_element, .{env.inner, self.inner, index, Value.from(value).inner});
  }

  pub fn has(self: Array, env: Env, index: u32) !bool {
    var b: bool = undefined;
    try call(c.napi_has_element, .{env.inner, self.inner, index, &b});

    return b;
  }

  pub fn delete(self: Array, env: Env, index: u32) !bool {
    var b: bool = undefined;
    try call(c.napi_delete_element, .{env.inner, self.inner, index, &b});

    return b;
  }

  pub fn init(env: Env, size: usize) !Array {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_array_with_length, .{env.inner, size, &raw});

    return Array { .inner = raw };
  }

  pub fn get(self: Array, env: Env, index: u32) !Value {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_element, .{env.inner, self.inner, index, &raw});

    return Value { .inner = raw };
  }
};

pub const String = struct {
  inner: c.napi_value,

  const encoding = enum {
    utf8,
    utf16,
    latin1,

    pub fn size(comptime self: encoding) type {
      return switch (self) {
        .utf16 => u16,
        .utf8, .latin1 => u8,
      };
    }
  };

  pub fn len(self: String, env: Env, comptime enc: encoding) !usize {
    var length: usize = undefined;

    try call(switch (enc) {
      .utf8 => c.napi_get_value_string_utf8,
      .utf16 => c.napi_get_value_string_utf16,
      .latin1 => c.napi_get_value_string_latin1,
    }, .{env.inner, self.inner, null, 0, &length});

    return length;
  }

  pub fn init(env: Env, comptime enc: encoding, value: []const enc.size()) !String {
    var raw: c.napi_value = undefined;

    try call(switch (enc) {
      .utf8 => c.napi_create_string_utf8,
      .utf16 => c.napi_create_string_utf16,
      .latin1 => c.napi_create_string_latin1,
    }, .{env.inner, value.ptr, value.len, &raw});

    return String { .inner = raw };
  }

  pub fn get(self: String, env: Env, comptime enc: encoding, allocator: std.mem.Allocator) ![]enc.size() {
    var length: usize = try self.len(env, enc);
    const slice = try allocator.alloc(enc.size(), length);

    errdefer allocator.free(slice);

    try call(switch (enc) {
      .utf8 => c.napi_get_value_string_utf8,
      .utf16 => c.napi_get_value_string_utf16,
      .latin1 => c.napi_get_value_string_latin1,
    }, .{env.inner, self.inner, slice.ptr, 1 + length, &length});

    return slice;
  }
};

pub const Object = struct {
  inner: c.napi_value,

  pub fn init(env: Env) !Object {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_object, .{env.inner, &raw});

    return Object { .inner = raw };
  }

  pub fn set(self: Object, env: Env, key: anytype, value: anytype) !void {
    try call(c.napi_set_property, .{env.inner, self.inner, Value.from(key).inner, Value.from(value).inner});
  }

  pub fn keys(self: Object, env: Env) !Array {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_property_names, .{env.inner, self.inner, &raw});

    return Array { .inner = raw };
  }

  pub fn set_named(self: Object, env: Env, comptime name: [:0]const u8, value: anytype) !void {
    try call(c.napi_set_named_property, .{env.inner, self.inner, name, Value.from(value).inner});
  }

  pub fn has(self: Object, env: Env, key: anytype) !bool {
    var result: bool = undefined;
    try call(c.napi_has_property, .{env.inner, self.inner, Value.from(key).inner, &result});

    return result;
  }

  pub fn delete(self: Object, env: Env, key: anytype) !bool {
    var result: bool = undefined;
    try call(c.napi_delete_property, .{env.inner, self.inner, Value.from(key).inner, &result});

    return result;
  }

  pub fn has_own(self: Object, env: Env, key: anytype) !bool {
    var result: bool = undefined;
    try call(c.napi_has_own_property, .{env.inner, self.inner, Value.from(key).inner, &result});

    return result;
  }

  pub fn has_named(self: Object, env: Env, comptime name: [:0]const u8) !bool {
    var result: bool = undefined;
    try call(c.napi_has_named_property, .{env.inner, self.inner, name, &result});

    return result;
  }

  pub fn get(self: Object, env: Env, key: anytype) !Value {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_property, .{env.inner, self.inner, Value.from(key).inner, &raw});

    return Value { .inner = raw };
  }

  pub fn get_named(self: Object, env: Env, comptime name: [:0]const u8) !Value {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_named_property, .{env.inner, self.inner, name, &raw});

    return Value { .inner = raw };
  }
};

pub const BigInt = struct {
  inner: c.napi_value,

  pub fn init(env: Env, value: anytype) !BigInt {
    const T = @TypeOf(value);
    var raw: c.napi_value = undefined;

    switch (@typeInfo(T)) {
      else => @compileError("expected int type, got: " ++ @typeName(T)),
      .ComptimeInt => try call(if (0 > value) c.napi_create_bigint_int64 else c.napi_create_bigint_uint64, .{env.inner, @as(if (0 > value) i64 else u64, value), &raw}),

      .Int => |info| switch (T) {
        i64 => try call(c.napi_create_bigint_int64, .{env.inner, @as(i64, value), &raw}),
        u64 => try call(c.napi_create_bigint_uint64, .{env.inner, @as(u64, value), &raw}),

        else => switch (info.bits) {
          0...63 => switch (info.signedness) {
            .signed => try call(c.napi_create_bigint_int64, .{env.inner, @as(i64, value), &raw}),
            .unsigned => try call(c.napi_create_bigint_uint64, .{env.inner, @as(u64, value), &raw}),
          },

          else => |bits| {
            const size = @ceil(bits / 64.0);
            const TT = std.meta.Int(.unsigned, @minimum(65535, 64 * size));
            const abs: TT align(8) = @intCast(TT, if (.unsigned == info.signedness) value else std.math.absCast(value));
            try call(c.napi_create_bigint_words, .{env.inner, @boolToInt(value <= 0), size, @ptrCast([*]const u64, &abs), &raw});
          },
        },
      }
    }

    return BigInt { .inner = raw };
  }

  pub fn get(self: BigInt, env: Env, comptime T: type) !T {
    switch (@typeInfo(T)) {
      else => @compileError("expected runtime int type, got: " ++ @typeName(T)),

      .Int => |info| switch (info.bits) {
        64 => {
          var value: T = undefined;
          var lossless: bool = undefined;

          try call(switch (info.signedness) {
            .signed => c.napi_get_value_bigint_int64,
            .unsigned => c.napi_get_value_bigint_uint64,
          }, .{env.inner, self.inner, &value, &lossless});

          return value;
        },

        0...63 => {
          var lossless: bool = undefined;
          var value: if (.unsigned == info.signedness) u64 else i64 = undefined;

          try call(switch (info.signedness) {
            .signed => c.napi_get_value_bigint_int64,
            .unsigned => c.napi_get_value_bigint_uint64,
          }, .{env.inner, self.inner, &value, &lossless});

          return std.math.cast(T, value);
        },

        else => |bits| {
          const size = @ceil(bits / 64.0);
          const TT = std.meta.Int(.unsigned, @minimum(65535, 64 * size));

          var sign: i32 = undefined;
          var len: usize = undefined;
          var value: TT align(8) = 0;
          try call(c.napi_get_value_bigint_words, .{env.inner, self.inner, null, &len, null});

          if (64 * len > @typeInfo(TT).Int.bits) return error.Overflow;
          try call(c.napi_get_value_bigint_words, .{env.inner, self.inner, &sign, &len, @ptrCast([*]u64, &value)});

          const v = try std.math.cast(T, value);

          return switch (info.signedness) {
            .signed => if (0 == sign) v else std.math.negateCast(v),
            .unsigned => if (0 == sign) v else (std.math.maxInt(T) - v + 1),
          };
        },
      }
    }
  }
};

pub const Number = struct {
  inner: c.napi_value,

  pub fn init(env: Env, value: anytype) !Number {
    const T = @TypeOf(value);
    var raw: c.napi_value = undefined;

    switch (@typeInfo(T)) {
      else => @compileError("expected number, got: " ++ @typeName(T)),
      .Float, .ComptimeFloat => try call(c.napi_create_double, .{env.inner, @floatCast(f64, value), &raw}),

      .ComptimeInt => {
        if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) try call(c.napi_create_int32, .{env.inner, @as(i32, value), &raw})
        else if (value >= std.math.minInt(i54) and value <= std.math.maxInt(i54)) try call(c.napi_create_int64, .{env.inner, @as(i64, value), &raw})

        else @compileError("comptime_int can't be represented as number (i54), use bigint instead");
      },

      // TODO: checked usize, isize lowering in serde
      .Int => |info| switch (info.bits) {
        33...53 => try call(c.napi_create_int64, .{env.inner, @as(i64, value), &raw}),
        54 => try call(c.napi_create_int64, .{env.inner, @as(i64, @as(i54, value)), &raw}),
        else => @compileError(@typeName(T) ++ " can't be represented as number (i54), use bigint instead"),

        0...32 => switch (info.signedness) {
          .signed => try call(c.napi_create_int32, .{env.inner, @as(i32, value), &raw}),
          .unsigned => try call(c.napi_create_uint32, .{env.inner, @as(u32, value), &raw}),
        },
      },
    }

    return Number { .inner = raw };
  }

  pub fn get(self: Number, env: Env, comptime T: type) !T {
    switch (@typeInfo(T)) {
      else => @compileError("expected runtime number type, got: " ++ @typeName(T)),

      .Float => {
        var value: f64 = undefined;
        try call(c.napi_get_value_double, .{env.inner, self.inner, &value});

        return @floatCast(T, value);
      },

      .Int => |info| switch (info.bits) {
        33...63 => {
          var value: i64 = undefined;
          try call(c.napi_get_value_int64, .{env.inner, self.inner, &value});

          return std.math.cast(T, value);
        },

        32 => {
          var value: T = undefined;

          try call(switch (info.signedness) {
            .signed => c.napi_get_value_int32,
            .unsigned => c.napi_get_value_uint32,
          }, .{env.inner, self.inner, &value});

          return value;
        },

        else => {
          var value: i64 = undefined;
          try call(c.napi_get_value_int64, .{env.inner, self.inner, &value});

          switch (info.signedness) {
            .signed => return @as(T, value),
            .unsigned => return if (0 <= value) @intCast(T, value) else error.Overflow,
          }
        },

        0...31 => switch (info.signedness) {
          .signed => {
            var value: i32 = undefined;
            try call(c.napi_get_value_int32, .{env.inner, self.inner, &value});

            return std.math.cast(T, value);
          },

          .unsigned => {
            var value: u32 = undefined;
            try call(c.napi_get_value_uint32, .{env.inner, self.inner, &value});

            return std.math.cast(T, value);
          },
        },
      },
    }
  }
};

pub const Buffer = struct {
  inner: c.napi_value,

  pub fn init(env: Env, size: usize) !Buffer {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_buffer, .{env.inner, size, null, &raw});

    return Buffer { .inner = raw };
  }

  pub fn len(self: Buffer, env: Env) !usize {
    var length: usize = undefined;
    var ptr: ?*anyopaque = undefined;
    try call(c.napi_get_buffer_info, .{env.inner, self.inner, &ptr, &length});

    return length;
  }

  pub fn get(self: Buffer, env: Env) ![]u8 {
    var ptr: [*]u8 = undefined;
    var length: usize = undefined;
    try call(c.napi_get_buffer_info, .{env.inner, self.inner, @ptrCast([*]?*anyopaque, &ptr), &length});

    return ptr[0..length];
  }

  pub fn dupe(env: Env, slice: []const u8) !Buffer {
    var ptr: [*]u8 = undefined;
    var raw: c.napi_value = undefined;
    try call(c.napi_create_buffer, .{env.inner, slice.len, @ptrCast([*]?*anyopaque, &ptr), &raw});

    @memcpy(ptr, slice.ptr, slice.len);

    return Buffer { .inner = raw };
  }

  pub fn external(env: Env, slice: []u8, data: anytype, finalizer: ?fn ([]u8, @TypeOf(data)) void) !Buffer {
    var raw: c.napi_value = undefined;

    if (null == finalizer) {
      const is_void = if (type == @TypeOf(data)) .Void == @typeInfo(data) else .Void == @typeInfo(@TypeOf(data));

      if (is_void) try call(c.napi_create_external_buffer, .{env.inner, slice.len, slice.ptr, null, null, &raw})

      else {
        if (@TypeOf(data) != std.mem.Allocator) @compileError("expected allocator, got: " ++ @typeName(@TypeOf(data)));

        const Info = struct {
          len: usize,
          ptr: [*]u8,
          a: std.mem.Allocator,
        };

        const wrapper = opaque {
          pub fn finalizer(_: c.napi_env, _: ?*anyopaque, ri: ?*anyopaque) callconv(.C) void {
            const info = @ptrCast(*Info, @alignCast(@alignOf(*Info), ri));

            defer A.destroy(info);
            info.a.free(info.ptr[0..info.len]);
          }
        };

        const info = try A.create(Info);

        info.a = data;
        info.len = slice.len;
        info.ptr = slice.ptr;

        errdefer A.destroy(info);
        try call(c.napi_create_external_buffer, .{env.inner, slice.len, slice.ptr, wrapper.finalizer, @ptrCast(* align(@alignOf(*Info)) anyopaque, info), &raw});
      }
    }

    else {
      const Info = struct {
        len: usize,
        ptr: [*]u8,
        data: @TypeOf(data),
        f: @typeInfo(@TypeOf(finalizer)).Optional.child,
      };

      const wrapper = opaque {
        pub fn finalizer(_: c.napi_env, _: ?*anyopaque, ri: ?*anyopaque) callconv(.C) void {
          const info = @ptrCast(*Info, @alignCast(@alignOf(*Info), ri));

          defer A.destroy(info);
          info.f(info.ptr[0..info.len], info.data);
        }
      };

      const info = try A.create(Info);

      info.data = data;
      info.f = finalizer.?;
      info.len = slice.len;
      info.ptr = slice.ptr;

      errdefer A.destroy(info);
      try call(c.napi_create_external_buffer, .{env.inner, slice.len, slice.ptr, wrapper.finalizer, @ptrCast(* align(@alignOf(*Info)) anyopaque, info), &raw});
    }

    return Buffer { .inner = raw };
  }
};

pub const TypedArray = struct {
  inner: c.napi_value,

  pub const types = enum {
    u8, i8,
    u16, i16,
    u32, i32,
    u64, i64,
    f32, f64,
    u8clamped,

    pub fn size(comptime self: types) comptime_int {
      return switch (self) {
        .u16, .i16 => 2,
        .u32, .i32, .f32 => 4,
        .u64, .i64, .f64 => 8,
        .u8, .i8, .u8clamped => 1,
      };
    }
  };

  pub fn len(self: TypedArray, env: Env) !usize {
    var length: usize = undefined;
    try call(c.napi_get_typedarray_info, .{env.inner, self.inner, null, &length, null, null, null});

    return length;
  }

  pub fn buffer(self: TypedArray, env: Env) !ArrayBuffer {
    var raw: c.napi_value = undefined;
    try call(c.napi_get_typedarray_info, .{env.inner, self.inner, null, null, null, &raw, null});

    return ArrayBuffer { .inner = raw };
  }

  pub fn get(self: TypedArray, env: Env, comptime T: type) ![]T {
    const wt = switch (T) {
      else => @compileError("unsupported type: " ++ @typeName(T)),
      u8, i8 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_1 },
      u24, i24 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_3 },
      u40, i40 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_5 },
      u48, i48 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_6 },
      u56, i56 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_7 },
      u72, i72 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_9 },
      u88, i88 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_11 },
      u96, i96 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_12 },
      u104, i104 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_13 },
      u112, i112 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_14 },
      u120, i120 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_15 },
      u16, i16, f16 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_2 },
      u32, i32, f32 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_4 },
      u64, i64, f64 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_8 },
      u80, i80, f80 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_10 },
      u128, i128, f128 => .{ .s = @sizeOf(T), .e = error.bytelength_not_multiple_of_16 },
    };

    var l: usize = undefined;
    var ptr: [*]T = undefined;
    var t: c.napi_typedarray_type = undefined;
    try call(c.napi_get_typedarray_info, .{env.inner, self.inner, &t, &l, @ptrCast([*]?*anyopaque, &ptr), null, null});

    const ts: u8 = switch (t) {
      else => unreachable,
      c.napi_int16_array, c.napi_uint16_array => 2,
      c.napi_int32_array, c.napi_uint32_array, c.napi_float32_array => 4,
      c.napi_int8_array, c.napi_uint8_array, c.napi_uint8_clamped_array => 1,
      c.napi_bigint64_array, c.napi_biguint64_array, c.napi_float64_array => 8,
    };

    if (ts != wt.s and (0 != ((l * ts) % wt.s))) return wt.e;

    return ptr[0..(l * ts / wt.s)];
  }

  pub fn init(env: Env, comptime t: types, ab: ArrayBuffer, offset: usize, length: usize) !TypedArray {
    const l = try ab.len(env);
    var raw: c.napi_value = undefined;
    if (l <= offset) return error.offset_out_of_bounds;

    const ll = l - offset;
    if (ll < length * t.size()) return error.length_out_of_bounds;

    switch (t) {
      .i8, .u8, .u8clamped => try call(c.napi_create_typedarray, .{env.inner, switch (t) {
        else => unreachable,
        .i8 => c.napi_int8_array,
        .u8 => c.napi_uint8_array,
        .u8clamped => c.napi_uint8_clamped_array,
      }, length, ab.inner, 0, &raw}),

      .f32 => {
        if (0 != (ll % 4)) return error.arraybuffer_length_not_multiple_of_4;
        try call(c.napi_create_typedarray, .{env.inner, c.napi_float32_array, length, ab.inner, 0, &raw});
      },

      .f64 => {
        if (0 != (ll % 8)) return error.arraybuffer_length_not_multiple_of_8;
        try call(c.napi_create_typedarray, .{env.inner, c.napi_float64_array, length, ab.inner, 0, &raw});
      },

      .i16, .u16 => {
        if (0 != (ll % 2)) return error.arraybuffer_length_not_multiple_of_2;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i16) c.napi_int16_array else c.napi_uint16_array, length, ab.inner, 0, &raw});
      },

      .i32, .u32 => {
        if (0 != (ll % 4)) return error.arraybuffer_length_not_multiple_of_4;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i32) c.napi_int32_array else c.napi_uint32_array, length, ab.inner, 0, &raw});
      },

      .i64, .u64 => {
        if (0 != (ll % 8)) return error.arraybuffer_length_not_multiple_of_8;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i64) c.napi_bigint64_array else c.napi_biguint64_array, length, ab.inner, 0, &raw});
      },
    }

    return TypedArray { .inner = raw };
  }
};

pub const ArrayBuffer = struct {
  inner: c.napi_value,

  pub fn init(env: Env, size: usize) !ArrayBuffer {
    var raw: c.napi_value = undefined;
    try call(c.napi_create_arraybuffer, .{env.inner, size, null, &raw});

    return ArrayBuffer { .inner = raw };
  }

  pub fn len(self: ArrayBuffer, env: Env) !usize {
    var length: usize = undefined;
    var ptr: ?*anyopaque = undefined;
    try call(c.napi_get_arraybuffer_info, .{env.inner, self.inner, &ptr, &length});

    return length;
  }

  pub fn get(self: ArrayBuffer, env: Env) ![]u8 {
    var ptr: [*]u8 = undefined;
    var length: usize = undefined;
    try call(c.napi_get_arraybuffer_info, .{env.inner, self.inner, @ptrCast([*]?*anyopaque, &ptr), &length});

    return ptr[0..length];
  }

  pub fn dupe(env: Env, slice: []const u8) !ArrayBuffer {
    var ptr: [*]u8 = undefined;
    var raw: c.napi_value = undefined;
    try call(c.napi_create_arraybuffer, .{env.inner, slice.len, @ptrCast([*]?*anyopaque, &ptr), &raw});

    @memcpy(ptr, slice.ptr, slice.len);
    return ArrayBuffer { .inner = raw };
  }

  pub fn cast(self: ArrayBuffer, env: Env, comptime t: TypedArray.types) !TypedArray {
    const length = try self.len(env);
    var raw: c.napi_value = undefined;

    switch (t) {
      .i8, .u8, .u8clamped => try call(c.napi_create_typedarray, .{env.inner, switch (t) {
        else => unreachable,
        .i8 => c.napi_int8_array,
        .u8 => c.napi_uint8_array,
        .u8clamped => c.napi_uint8_clamped_array,
      }, length, self.inner, 0, &raw}),

      .f32 => {
        if (0 != (length % 4)) return error.length_not_multiple_of_4;
        try call(c.napi_create_typedarray, .{env.inner, c.napi_float32_array, length / 4, self.inner, 0, &raw});
      },

      .f64 => {
        if (0 != (length % 8)) return error.length_not_multiple_of_8;
        try call(c.napi_create_typedarray, .{env.inner, c.napi_float64_array, length / 8, self.inner, 0, &raw});
      },

      .i16, .u16 => {
        if (0 != (length % 2)) return error.length_not_multiple_of_2;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i16) c.napi_int16_array else c.napi_uint16_array, length / 2, self.inner, 0, &raw});
      },

      .i32, .u32 => {
        if (0 != (length % 4)) return error.length_not_multiple_of_4;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i32) c.napi_int32_array else c.napi_uint32_array, length / 4, self.inner, 0, &raw});
      },

      .i64, .u64 => {
        if (0 != (length % 8)) return error.length_not_multiple_of_8;
        try call(c.napi_create_typedarray, .{env.inner, if (t == .i64) c.napi_bigint64_array else c.napi_biguint64_array, length / 8, self.inner, 0, &raw});
      },
    }

    return TypedArray { .inner = raw };
  }

  pub fn external(env: Env, slice: []u8, data: anytype, finalizer: ?fn ([]u8, @TypeOf(data)) void) !ArrayBuffer {
    var raw: c.napi_value = undefined;

    if (null == finalizer) {
      const is_void = if (type == @TypeOf(data)) .Void == @typeInfo(data) else .Void == @typeInfo(@TypeOf(data));
      if (is_void) try call(c.napi_create_external_arraybuffer, .{env.inner, slice.ptr, slice.len, null, null, &raw})

      else {
        if (@TypeOf(data) != std.mem.Allocator) @compileError("expected allocator, got: " ++ @typeName(@TypeOf(data)));

        const Info = struct {
          len: usize,
          ptr: [*]u8,
          a: std.mem.Allocator,
        };

        const wrapper = opaque {
          pub fn finalizer(_: c.napi_env, _: ?*anyopaque, ri: ?*anyopaque) callconv(.C) void {
            const info = @ptrCast(*Info, @alignCast(@alignOf(*Info), ri));

            defer A.destroy(info);
            info.a.free(info.ptr[0..info.len]);
          }
        };

        const info = try A.create(Info);

        info.a = data;
        info.len = slice.len;
        info.ptr = slice.ptr;

        errdefer A.destroy(info);
        try call(c.napi_create_external_arraybuffer, .{env.inner, slice.ptr, slice.len, wrapper.finalizer, @ptrCast(* align(@alignOf(*Info)) anyopaque, info), &raw});
      }
    }

    else {
      const Info = struct {
        len: usize,
        ptr: [*]u8,
        data: @TypeOf(data),
        f: @typeInfo(@TypeOf(finalizer)).Optional.child,
      };

      const wrapper = opaque {
        pub fn finalizer(_: c.napi_env, _: ?*anyopaque, ri: ?*anyopaque) callconv(.C) void {
          const info = @ptrCast(*Info, @alignCast(@alignOf(*Info), ri));

          defer A.destroy(info);
          info.f(info.ptr[0..info.len], info.data);
        }
      };

      const info = try A.create(Info);

      info.data = data;
      info.f = finalizer.?;
      info.len = slice.len;
      info.ptr = slice.ptr;

      errdefer A.destroy(info);
      try call(c.napi_create_external_arraybuffer, .{env.inner, slice.ptr, slice.len, wrapper.finalizer, @ptrCast(* align(@alignOf(*Info)) anyopaque, info), &raw});
    }

    return ArrayBuffer { .inner = raw };
  }
};

pub const Function = struct {
  inner: c.napi_value,

  pub fn init(env: Env, comptime name: [:0]const u8, comptime f: fn (env: Env, info: CallbackInfo) anyerror!Value) !Function {
    const wrapper = opaque {
      pub fn zig(e: Env, ri: c.napi_callback_info) !Value {
        return try f(e, CallbackInfo { .inner = ri });
      }

      pub fn callback(re: c.napi_env, ri: c.napi_callback_info) callconv(.C) c.napi_value {
        if (zig(Env.init(re), ri)) |x| { return x.inner; }
        else |err| Env.init(re).throw_error(@errorName(err)) catch {};

        return null;
      }
    };

    var raw: c.napi_value = undefined;
    try call(c.napi_create_function, .{env.inner, name, name.len, wrapper.callback, null, &raw});

    return Function { .inner = raw };
  }
};

const Class = struct {};