const std = @import("std");
const allocator = std.heap.c_allocator;
const napi = @import("./napi/headers/c.zig");

pub usingnamespace napi;
pub const serde = @import("./serde.zig");

pub const bind = opaque {
  // pub fn class() void {}
  pub const function = @import("./bind/function.zig").bind;
};

pub const js_type = enum {
  js_null, js_number, js_string, js_symbol, js_object,
  js_bigint, js_boolean, js_external, js_function, js_undefined,
};

pub fn register(comptime f: fn(env, object) anyerror!void) void {
  const wrapper = opaque {
    fn napi_register_module_v1(re: napi.napi_env, m: napi.napi_value) callconv(.C) napi.napi_value {
      const e = env.init(re);
      const exports = object.init(m);

      f(e, exports) catch |er| {
        defer std.os.exit(1);
        std.log.err("failed to register module: {s}", .{er});
      };

      return exports.raw;
    }
  };

  @export(wrapper.napi_register_module_v1, .{ .linkage = .Strong, .name = "napi_register_module_v1" });
}

pub const safe = @import("./napi/c-napi/safe.zig").call;

/// js runtime types ///

pub const env = struct {
  raw: napi.napi_env,

  pub fn init(raw: napi.napi_env) env { return env { .raw = raw }; }
  pub fn create(self: env, v: anytype) !value { return serde.init(self).serialize(v); }
  pub fn throw_error(self: env, e: [:0]const u8) !void { try safe(napi.napi_throw_error, .{self.raw, null, e}); }

  pub fn eval(self: env, script: string) !value {
    var raw: napi.napi_value = undefined;
    try safe(napi.napi_run_script, .{self.raw, script.raw, &raw});

    return value.init(raw);
  }
};

pub const value = struct {
  raw: napi.napi_value,

  pub fn init(raw: napi.napi_value) value { return value { .raw = raw }; }

  pub fn typeof(self: value, e: env) !js_type {
    var t: napi.napi_valuetype = undefined;
    try safe(napi.napi_typeof, .{e.raw, self.raw, &t});

    return switch (t) {
      else => unreachable,
      napi.napi_null => js_type.js_null,
      napi.napi_number => js_type.js_number,
      napi.napi_string => js_type.js_string,
      napi.napi_symbol => js_type.js_symbol,
      napi.napi_object => js_type.js_object,
      napi.napi_bigint => js_type.js_bigint,
      napi.napi_boolean => js_type.js_boolean,
      napi.napi_external => js_type.js_external,
      napi.napi_function => js_type.js_function,
      napi.napi_undefined => js_type.js_undefined,
    };
  }
};



/// specialized js types ///

// TODO: runtime support
pub const object = struct {
  raw: napi.napi_value,

  pub fn init(raw: napi.napi_value) object { return object { .raw = raw }; }
  pub fn set(self: object, e: env, k: [:0]const u8, v: value) !void { try safe(napi.napi_set_named_property, .{e.raw, self.raw, k, v.raw}); }
  pub fn new(e: env) !object { var raw: napi.napi_value = undefined; try safe(napi.napi_create_object, .{e.raw, &raw}); return object { .raw = raw }; }
  pub fn get(self: object, e: env, k: [:0]const u8) !value { var raw: napi.napi_value = undefined; try safe(napi.napi_get_named_property, .{e.raw, self.raw, k, &raw}); return value { .raw = raw }; }
};

// TODO: runtime support
pub const array = struct {
  raw: napi.napi_value,

  pub fn init(raw: napi.napi_value) array { return array { .raw = raw }; }
  pub fn set(self: array, e: env, index: u32, v: value) !void { try safe(napi.napi_set_element, .{e.raw, self.raw, index, v.raw}); }
  pub fn len(self: array, e: env) !usize { var l: u32 = undefined; try safe(napi.napi_get_array_length, .{e.raw, self.raw, &l}); return l; }
  pub fn new(e: env, length: u32) !array { var raw: napi.napi_value = undefined; try safe(napi.napi_create_array_with_length, .{e.raw, length, &raw}); return array { .raw = raw }; }
  pub fn get(self: array, e: env, index: u32) !value { var v: napi.napi_value = undefined; try safe(napi.napi_get_element, .{e.raw, self.raw, index, &v}); return value { .raw = v }; }
};

pub const string = struct {
  raw: napi.napi_value,

  pub const encoding = enum {
    utf8,
    utf16,
    latin1,

    pub fn size(self: encoding) type {
      return switch (self) {
        .utf8 => u8,
        .utf16 => u16,
        .latin1 => u8,
      };
    }
  };

  pub fn init(raw: napi.napi_value) string { return string { .raw = raw }; }

  pub fn new(e: env, comptime c: encoding, s: anytype) !string {
    const T = c.size();
    var raw: napi.napi_value = undefined;
    const slice = std.mem.sliceAsBytes(s[0..]);

    try safe(switch (c) {
      .utf8 => napi.napi_create_string_utf8,
      .utf16 => napi.napi_create_string_utf16,
      .latin1 => napi.napi_create_string_latin1,
    }, .{e.raw, @ptrCast([*]const T, slice.ptr), s.len, &raw});

    return string { .raw = raw };
  }

  pub fn get(self: string, e: env, comptime c: encoding, A: std.mem.Allocator) ![]c.size() {
    const T = c.size();
    var size: usize = undefined;

    const f = switch (c) {
      .utf8 => napi.napi_get_value_string_utf8,
      .utf16 => napi.napi_get_value_string_utf16,
      .latin1 => napi.napi_get_value_string_latin1,
    };

    try safe(f, .{e.raw, self.raw, null, 0, &size});
    const s = try A.alloc(T, size); errdefer A.free(s);
    try safe(f, .{e.raw, self.raw, s.ptr, 1 + size, &size});

    return s;
  }
};