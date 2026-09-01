const http = require('http');
const iconv = require('iconv-lite');

const schoolName = process.argv[2] || '양동';

console.log(`🔍 [Comcigan CLI] 컴시간 서버 접속 및 학교 검색 중: "${schoolName}"...`);

const landingUrl = 'http://xn--s39aj90b0nb2xw6xh.kr';

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

function encodeCP949Hex(str) {
  const buf = iconv.encode(str, 'euc-kr');
  return Array.from(buf).map(b => '%' + b.toString(16).toLowerCase().padStart(2, '0')).join('');
}

(async () => {
  try {
    const landingBuf = await fetchUrl(landingUrl);
    const landingHtml = landingBuf.toString('utf-8');

    const frameMatch = landingHtml.match(/<frame\s+[^>]*src=["']([^"']+)["']/i);
    if (!frameMatch) throw new Error('컴시간 프레임 URL추출 실패');

    const frameUrl = new URL(frameMatch[1], landingUrl).href;
    const baseUrl = `${new URL(frameUrl).protocol}//${new URL(frameUrl).host}`;

    const frameBuf = await fetchUrl(frameUrl);
    const frameHtml = frameBuf.toString('utf-8');

    const searchPathMatch = frameHtml.match(/url\s*:\s*'\s*\.\/([^']+)'/i);
    if (!searchPathMatch) throw new Error('컴시간 검색 경로 추출 실패');

    const extractCode = '/' + searchPathMatch[1];
    const hexQuery = encodeCP949Hex(schoolName);
    const searchUrl = baseUrl + extractCode + hexQuery;

    const resultBuf = await fetchUrl(searchUrl);
    let resultText = resultBuf.toString('utf-8');

    const cleanJson = resultText.substring(0, resultText.lastIndexOf('}') + 1);
    const data = JSON.parse(cleanJson);
    const list = data['학교검색'] || [];

    console.log(`\n✅ [Comcigan CLI] 검색 성공! (서버: ${baseUrl})`);
    console.log(`총 ${list.length}건 검색 결과:`);
    console.log('==================================================');
    list.forEach((item, idx) => {
      console.log(`${idx + 1}. [지역: ${item[1]}] ${item[2]} ➔ 학교코드: \x1b[36m${item[3]}\x1b[0m`);
    });
    console.log('==================================================\n');
  } catch (e) {
    console.error('❌ 검색 중 오류 발생:', e.message);
  }
})();
