const lib = require('./lib.node');

console.log(lib);

(async () => {
  console.log((await lib.zig)())
})()

// const p = lib.zig(new Uint32Array(4), new Uint8Array(5));

// (async () => {
//   const i = setInterval(() => console.log('500ms passed'), 500);

//   try {
//     const r = await p;
//     console.log('zig async returned:', r);
//   }

//   catch (err) {
//     console.log('async threw error:', err);
//   }

//   finally {
//     clearInterval(i);
//   }
// })();