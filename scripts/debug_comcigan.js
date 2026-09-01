const http = require('http');

http.get('http://xn--s39aj90b0nb2xw6xh.kr', (res) => {
  let chunks = [];
  res.on('data', chunk => chunks.push(chunk));
  res.on('end', async () => {
    const html = Buffer.concat(chunks).toString('utf-8');
    console.log('Landing HTML:', html);
    const frameMatch = html.match(/<frame\s+[^>]*src=["']([^"']+)["']/i);
    if (frameMatch) {
      console.log('Frame src:', frameMatch[1]);
      const frameUrl = new URL(frameMatch[1], 'http://xn--s39aj90b0nb2xw6xh.kr').href;
      http.get(frameUrl, (fRes) => {
        let fChunks = [];
        fRes.on('data', fChunk => fChunks.push(fChunk));
        fRes.on('end', () => {
          const fHtml = Buffer.concat(fChunks).toString('utf-8');
          console.log('Frame HTML snippet:', fHtml.substring(0, 400));
          const schoolRaMatch = fHtml.match(/url\s*:\s*'\s*\.\/([^']+)'/i);
          console.log('SchoolRa Match:', schoolRaMatch ? schoolRaMatch[1] : 'NONE');
        });
      });
    }
  });
});
