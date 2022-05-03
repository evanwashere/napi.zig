const std = @import("std");
const napi = @import("./napi.zig");

pub usingnamespace struct {
  env: napi.env,
  const serde = @This();

  pub fn init(env: napi.env) serde {
    return serde { .env = env };
  }

  pub fn serialize(self: serde, v: anytype) !napi.value {
    const T = @TypeOf(v);
    const I = @typeInfo(T);

    if (T == type) switch (@typeInfo(v)) {
      .Enum => return serde.types.@"enum".serialize(self.env, v),
      .Void => return serde.types.@"undefined".serialize(self.env),
      else => @compileError("unsupported meta type: " ++ @typeInfo(v)),
    };

    switch (I) {
      .Null => return serde.types.@"null".serialize(self.env),
      .Enum => return serde.types.@"enum".serialize(self.env, v),
      .Bool => return serde.types.@"bool".serialize(self.env, v),
      else => @compileError("unsupported type: " ++ @typeName(T)),
      .Void => return serde.types.@"undefined".serialize(self.env),
      .ErrorSet => return serde.types.@"error".serialize(self.env, v),
      .Int, .Float, .ComptimeInt, .ComptimeFloat => return serde.types.@"number".serialize(self.env, v),
      .Optional => if (v) |x| return self.serialize(x) else return serde.types.@"null".serialize(self.env),
      .ErrorUnion => if (v) |x| return self.serialize(x) else |x| return serde.types.@"error".serialize(self.env, x),

      .Union => switch (T) {
        else => return serde.types.@"union".serialize(self.env, v),
        serde.string => return serde.types.@"string".serialize(self.env, v),
      },

      .Struct => switch (T) {
        else => return serde.types.@"struct".serialize(self.env, v),
        napi.value, napi.array, napi.string, napi.object => return napi.value.init(v.raw),
      },
    }
  }

  pub const string = union(enum) {
    static: []const u8,

    alloced: struct {
      slice: []u8,
      alloc: std.mem.Allocator,
    },

    pub fn from(s: anytype) string {
      return string {
        .static = std.mem.sliceAsBytes(s[0..]),
      };
    }

    pub fn new(s: anytype, allocator: std.mem.Allocator) !string {
      return string {
        .alloced = .{
          .alloc = allocator,
          .slice = if ([]u8 == @TypeOf(s)) s else try allocator.alloc(u8, s),
        },
      };
    }
  };

  // TODO: slice, array, pointer
  pub const types = opaque {
    pub const @"null" = opaque {
      pub fn serialize(env: napi.env) !napi.value {
        var raw: napi.napi_value = undefined;
        try napi.safe(napi.napi_get_null, .{env.raw, &raw});

        return napi.value { .raw = raw };
      }
    };

    pub const @"undefined" = opaque {
      pub fn serialize(env: napi.env) !napi.value {
        var raw: napi.napi_value = undefined;
        try napi.safe(napi.napi_get_undefined, .{env.raw, &raw});

        return napi.value { .raw = raw };
      }
    };

    pub const @"bool" = opaque {
      pub fn serialize(env: napi.env, v: bool) !napi.value {
        var raw: napi.napi_value = undefined;
        try napi.safe(napi.napi_get_boolean, .{env.raw, v, &raw});

        return napi.value { .raw = raw };
      }

      pub fn deserialize(env: napi.env, v: napi.value) !bool {
        var raw: bool = undefined;
        try napi.safe(napi.napi_get_value_bool, .{env.raw, v.raw, &raw});

        return raw;
      }
    };

    pub const @"error" = opaque {
      pub fn serialize(env: napi.env, v: anyerror) !napi.value {
        var raw: napi.napi_value = undefined;
        const s = try napi.string.new(env, .latin1, @errorName(v));
        try napi.safe(napi.napi_create_error, .{env.raw, null, s.raw, &raw});

        return napi.value { .raw = raw };
      }
    };

    pub const @"union" = opaque {
      pub fn serialize(env: napi.env, v: anytype) !napi.value {
        const T = @TypeOf(v);
        const I = @typeInfo(T);
        const S = serde.init(env);

        switch (I) {
          else => @compileError("expected union, got: " ++ @typeName(T)),

          .Union => |info| {
            const tag = std.meta.Tag(T);
            const object = try napi.object.new(env);

            inline for (info.fields) |f| {
              if (@as(tag, v) == @field(tag, f.name)) {
                try object.set(env, f.name[0.. :0], try S.serialize(@field(v, f.name)));
              }
            }

            return napi.value.init(object.raw);
          },
        }

        unreachable;
      }
    };

    pub const @"enum" = opaque {
      pub fn serialize(env: napi.env, v: anytype) !napi.value {
        const T = @TypeOf(v);
        const I = @typeInfo(T);
        const S = serde.init(env);
        var raw: napi.napi_value = undefined;

        switch (I) {
          else => @compileError("expected enum, got: " ++ @typeName(T)),
          .Enum => return serde.types.number.serialize(env, @enumToInt(v)),

          .Type => switch (@typeInfo(v)) {
            else => @compileError("expected enum type, got: " ++ @typeName(v)),

            .Enum => |info| {
              try napi.safe(napi.napi_create_object, .{env.raw, &raw}); const o = napi.object.init(raw);
              inline for (info.fields) |f| { try o.set(env, f.name[0.. :0], try S.serialize(@field(v, f.name))); }
            },
          },
        }

        return napi.value { .raw = raw };
      }
    };

    pub const @"string" = opaque {
      pub fn deserialize(env: napi.env, v: napi.value, A: std.mem.Allocator) !serde.string {
        return try serde.string.new(try napi.string.init(v.raw).get(env, .utf8, A), A);
      }

      pub fn serialize(env: napi.env, v: serde.string) !napi.value {
        switch (v) {
          .static => return napi.value.init((try napi.string.new(env, .utf8, v.static)).raw),
          .alloced => |x| return napi.value.init((try napi.string.new(env, .utf8, x.slice)).raw),
        }
      }
    };

    pub const @"struct" = opaque {
      pub fn serialize(env: napi.env, v: anytype) !napi.value {
        const T = @TypeOf(v);
        const I = @typeInfo(T);
        const S = serde.init(env);
        var raw: napi.napi_value = undefined;

        switch (I) {
          else => @compileError("expected struct, got: " ++ @typeName(T)),

          .Struct => |info| switch(info.is_tuple) {
            false => {
              try napi.safe(napi.napi_create_object, .{env.raw, &raw}); const o = napi.object.init(raw);
              inline for (info.fields) |f| { try o.set(env, f.name[0.. :0], try S.serialize(@field(v, f.name))); }
            },

            true => {
              try napi.safe(napi.napi_create_array_with_length, .{env.raw, info.fields.len, &raw}); const a = napi.array.init(raw);
              inline for (info.fields) |field, offset| { try a.set(env, offset, try S.serialize(@field(v, field.name))); }
            },
          },
        }

        return napi.value { .raw = raw };
      }
    };

    pub const @"number" = opaque {
      pub fn serialize(env: napi.env, v: anytype) !napi.value {
        const T = @TypeOf(v);
        const I = @typeInfo(T);
        var raw: napi.napi_value = undefined;

        switch (I) {
          else => @compileError("expected number, got: " ++ @typeName(@TypeOf(v))),
          .ComptimeInt => try napi.safe(napi.napi_create_int64, .{env.raw, @as(i64, @as(i53, v)), &raw}),
          .Float, .ComptimeFloat => try napi.safe(napi.napi_create_double, .{env.raw, @as(f64, v), &raw}),

          .Int => |info| switch (T) {
            i64 => try napi.safe(napi.napi_create_bigint_int64, .{env.raw, v, &raw}),
            u64 => try napi.safe(napi.napi_create_bigint_uint64, .{env.raw, v, &raw}),
            i8, i16, i32 => try napi.safe(napi.napi_create_int32, .{env.raw, @as(i32, v), &raw}),
            u8, u16, u32 => try napi.safe(napi.napi_create_uint32, .{env.raw, @as(u32, v), &raw}),
            usize, isize => try napi.safe(napi.napi_create_int64, .{env.raw, @intCast(i64, v), &raw}),
            u128 => try napi.safe(napi.napi_create_bigint_words, .{env.raw, 0, 2, @ptrCast([*]const u64, &v), &raw}),
            i128 => try napi.safe(napi.napi_create_bigint_words, .{env.raw, @boolToInt(v <= 0), 2, @ptrCast([*]const u64, &std.math.absCast(v)), &raw}),

            else => {
              var sign = info.signedness;

              switch (info.bits) {
                else => @compileError("unsupported integer width"),
                33...53 => try napi.safe(napi.napi_create_int64, .{env.raw, @as(i64, v), &raw}),

                0...31 => switch (sign) {
                  .signed => try napi.safe(napi.napi_create_int32, .{env.raw, @as(i32, v), &raw}),
                  .unsigned => try napi.safe(napi.napi_create_uint32, .{env.raw, @as(u32, v), &raw}),
                },

                54...63 => switch (sign) {
                  .signed => try napi.safe(napi.napi_create_bigint_int64, .{env.raw, @as(i64, v), &raw}),
                  .unsigned => try napi.safe(napi.napi_create_bigint_uint64, .{env.raw, @as(u64, v), &raw}),
                },
              }
            },
          },
        }

        return napi.value { .raw = raw };
      }

      pub fn deserialize(env: napi.env, comptime T: type, v: napi.value) !T {
        switch (@typeInfo(T)) {
          else => @compileError("expected number type, got: " ++ @typeName(T)),

          .Float => {
            var raw: f64 = undefined;
            try napi.safe(napi.napi_get_value_double, .{env.raw, v.raw, &raw});

            return if (T == f64) raw else @floatCast(T, raw);
          },

          .Int => switch (T) {
            else => @compileError("unsupported integer type: " ++ @typeName(T)),

            i18, i16 => {
              var raw: i32 = undefined;
              try napi.safe(napi.napi_get_value_int32, .{env.raw, v.raw, &raw});

              return std.math.cast(T, raw);
            },

            u18, u16 => {
              var raw: u32 = undefined;
              try napi.safe(napi.napi_get_value_uint32, .{env.raw, v.raw, &raw});

              return std.math.cast(T, raw);
            },

            usize, isize => {
              var raw: i64 = undefined;
              try napi.safe(napi.napi_get_value_int64, .{env.raw, v.raw, &raw});

              return std.math.cast(T, raw);
            },

            u32, i32, u64, i64 => {
              var raw: T = undefined;

              try napi.safe(switch (T) {
                else => unreachable,
                i32 => napi.napi_get_value_int32,
                u32 => napi.napi_get_value_uint32,
                i64 => napi.napi_get_value_bigint_int64,
                u64 => napi.napi_get_value_bigint_uint64,
              }, .{env.raw, v.raw, &raw});

              return raw;
            },
          },
        }
      }
    };
  };
};