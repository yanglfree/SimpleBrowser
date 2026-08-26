import { createServer } from 'node:http';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { toolDirectory } from './reader-core-source.mjs';

const fixtureRoot = path.join(toolDirectory, 'fixtures');
const fixtureSlugs = new Set((await readdir(fixtureRoot, { withFileTypes: true }))
  .filter(entry => entry.isDirectory())
  .map(entry => entry.name));
const port = Number(process.env.ZHUO_READER_FIXTURE_PORT || 4173);

const server = createServer(async (request, response) => {
  const url = new URL(request.url || '/', 'http://127.0.0.1');
  if (url.pathname === '/health') {
    response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('ok');
    return;
  }
  const match = url.pathname.match(/^\/fixtures\/([a-z0-9-]+)$/);
  if (!match || !fixtureSlugs.has(match[1])) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('fixture not found');
    return;
  }
  const html = await readFile(path.join(fixtureRoot, match[1], 'source.html'));
  response.writeHead(200, {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store'
  });
  response.end(html);
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Reader fixture server: http://127.0.0.1:${port}`);
  for (const slug of fixtureSlugs) console.log(`http://127.0.0.1:${port}/fixtures/${slug}`);
});
