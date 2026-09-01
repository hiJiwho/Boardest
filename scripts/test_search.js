const http = require('http');
const iconv = require('iconv-lite');

async function testSearch(kw) {
  const eucBytes = iconv.encode(kw, 'euc-kr');
  const hexStr = Array.from(eucBytes).map(b => '%' + b.toString(16).padStart(2, '0')).join('');
  const hexStrUpper = Array.from(eucBytes).map(b => '%' + b.toString(16).toUpperCase().padStart(2, '0')).join('');
  
  const urls = [
    `http://comci.net:4082/36179?17384l${hexStr}`,
    `http://comci.net:4082/36179?17384l${hexStrUpper}`,
    `http://comci.net:4082/36179?17384l${encodeURIComponent(kw)}`,
  ];

  for (const u of urls) {
    console.log('Testing URL:', u);
    await new Promise(res => {
      http.get(u, (r) => {
        let b = [];
        r.on('data', c => b.push(c));
        r.on('end', () => {
          const raw = iconv.decode(Buffer.concat(b), 'euc-kr');
          console.log('  Response snippet:', raw.substring(0, 150));
          res();
        });
      });
    });
  }
}

testSearch('양동');
