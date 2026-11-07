import { createApp } from './app.js';

const port = Number(process.env.PORT ?? 8080);
const version = process.env.APP_VERSION ?? 'dev';

const server = createApp({ version });

server.listen(port, () => {
  console.log(JSON.stringify({ msg: 'listening', port, version }));
});

// Kubernetes sends SIGTERM before it removes a pod: finish open requests, then exit.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(JSON.stringify({ msg: 'shutting down', signal }));
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}
