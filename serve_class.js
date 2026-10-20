const http = require('http');
const fs = require('fs');
const path = require('path');

const baseDir = path.resolve(__dirname, 'apps/boardest/build/web');

const mimeTypes = {
  '.html': 'text/html; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.wasm': 'application/wasm',
};

function createServer() {
  return http.createServer((req, res) => {
    let reqPath = decodeURI(req.url.split('?')[0]);
    if (reqPath === '/' || reqPath === '') reqPath = '/index.html';
    let filePath = path.join(baseDir, reqPath);

    if (!fs.existsSync(filePath)) {
      filePath = path.join(baseDir, 'index.html');
    }

    try {
      const stat = fs.statSync(filePath);
      if (stat.isDirectory()) {
        filePath = path.join(filePath, 'index.html');
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = mimeTypes[ext] || 'application/octet-stream';

      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(500);
          res.end('Error loading file');
          return;
        }
        res.writeHead(200, {
          'Content-Type': contentType,
          'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
          'Expires': '0',
          'Access-Control-Allow-Origin': '*',
        });
        res.end(data);
      });
    } catch (e) {
      res.writeHead(404);
      res.end('Not found');
    }
  });
}

[8765, 9000].forEach((port) => {
  const s = createServer();
  s.listen(port, '0.0.0.0', () => {
    console.log(`Boardest preview server running at http://localhost:${port}/`);
  }).on('error', (err) => {
    console.log(`Port ${port} error: ${err.message}`);
  });
});
