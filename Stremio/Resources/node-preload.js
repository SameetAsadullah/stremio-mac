// Runs before server.js (node -r). server.js listens on every interface and hard-codes 11470
// with fallbacks up to 11474. This moves those ports to STREMIO_SERVER_PORT and binds them to
// loopback, and exits when the app that started us goes away.
const net = require('net');
const base = Number(process.env.STREMIO_SERVER_PORT || 11470);
const listen = net.Server.prototype.listen;
const ours = (p) => Number.isInteger(Number(p)) && Number(p) >= 11470 && Number(p) <= 11474;
net.Server.prototype.listen = function (...args) {
  const first = args[0];
  if (first && typeof first === 'object' && ours(first.port)) {
    args[0] = Object.assign({}, first, { port: Number(first.port) - 11470 + base, host: '127.0.0.1' });
  } else if (ours(first)) {
    args[0] = Number(first) - 11470 + base;
    if (typeof args[1] !== 'string') args.splice(1, 0, '127.0.0.1');
  }
  return listen.apply(this, args);
};

// The app holds the write end of our stdin. It closes when the app exits, however it exits.
process.stdin.on('end', () => process.exit(0));
process.stdin.on('error', () => process.exit(0));
process.stdin.resume();
