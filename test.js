const lib = require('./lib.node');

console.log(lib);

const p = lib.zig('1');

(async () => {
  const i = setInterval(() => console.log('500ms passed'), 500);

  try {
    const r = await p;
    console.log('zig async returned:', r);
  }

  catch (err) {
    console.log('async threw error:', err);
  }

  finally {
    clearInterval(i);
  }
})();