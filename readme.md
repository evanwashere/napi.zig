<h1 align=center>napi.zig</h1>
<div align=center>tiny and fast node-api bindings for zig</div>

<br />

## Features
- 🚀 async functions run in parallel
- ⛓️ expose c and zig functions to js
- 🔨 does not require node-gyp to build
- [WIP] ✨ seamless serde between js and zig types
- 🎯 compile to any architecture with zig cross-compilation

<br />

## Examples
- [print](https://github.com/evanwashere/napi.zig/blob/master/examples/print.zig)
- [sleep](https://github.com/evanwashere/napi.zig/blob/master/examples/sleep.zig)
- [base64](https://github.com/evanwashere/napi.zig/blob/master/examples/base64.zig)

*more examples in [examples/](https://github.com/evanwashere/napi.zig/tree/master/examples) folder*

```zig
const std = @import("std");
const napi = @import("./src/napi.zig");
const allocator = std.heap.c_allocator;

comptime {
  napi.register(init);
}

fn init(env: napi.env, exports: napi.object) !void {
  try exports.set(env, "add", try napi.bind.function(env, add, "add", allocator));
}

fn add(a: u32, b: u32) u32 {
  return a + b;
}
```

## License

MIT © [Evan](https://github.com/evanwashere)