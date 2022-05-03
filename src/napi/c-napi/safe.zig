const std = @import("std");
const c = @import("../headers/c.zig");

pub fn call(comptime f: anytype, args: anytype) !void {
  const status = @call(.{}, f, args);

  // headers/node/src/js_native_api_types.h
  if (status != c.napi_ok) return switch (status) {
    else => unreachable,
    c.napi_closing => error.closing,
    c.napi_cancelled => error.cancelled,
    c.napi_queue_full => error.queue_full,
    c.napi_invalid_arg => error.invalid_arg,
    c.napi_would_deadlock => error.would_deadlock,
    c.napi_generic_failure => error.generic_failure,
    c.napi_pending_exception => error.pending_exception,
    c.napi_escape_called_twice => error.escape_called_twice,
    c.napi_handle_scope_mismatch => error.handle_scope_mismatch,
    c.napi_callback_scope_mismatch => error.callback_scope_mismatch,

    c.napi_name_expected => error.expected_name,
    c.napi_date_expected => error.expected_date,
    c.napi_array_expected => error.expected_array,
    c.napi_number_expected => error.expected_number,
    c.napi_string_expected => error.expected_string,
    c.napi_object_expected => error.expected_object,
    c.napi_bigint_expected => error.expected_bigint,
    c.napi_boolean_expected => error.expected_boolean,
    c.napi_function_expected => error.expected_function,
    c.napi_arraybuffer_expected => error.expected_arraybuffer,
    c.napi_detachable_arraybuffer_expected => error.expected_detachable_arraybuffer,
  };
}