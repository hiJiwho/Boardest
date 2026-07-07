const axios = require('axios');
const iconv = require('iconv-lite');

const DEFAULT_URL = 'http://xn--s39aj90b0nb2xw6xh.kr';
let comciganConfig = {
  baseUrl: null,
  extractCode: null,
  scData: null,
};

async function initComcigan() {
  console.log('Initializing Comcigan...');
  const res1 = await axios.get(DEFAULT_URL, { responseType: 'arraybuffer', timeout: 7000 });
  let html = iconv.decode(res1.data, 'utf-8');
  if (!html.includes('frame')) {
    html = iconv.decode(res1.data, 'euc-kr');
  }

  const frameMatch = html.match(/<frame\s+[^>]*src=["']([^"']+)["']/i);
  if (!frameMatch) throw new Error('Failed to find frame source');

  const framePath = frameMatch[1];
  const resolvedUrl = new URL(framePath, DEFAULT_URL).toString();
  console.log('Resolved Frame URL:', resolvedUrl);
  const frameUrlObj = new URL(resolvedUrl);
  comciganConfig.baseUrl = `${frameUrlObj.protocol}//${frameUrlObj.host}`;

  const res2 = await axios.get(resolvedUrl, { responseType: 'arraybuffer', timeout: 7000 });
  const frameHtml = iconv.decode(res2.data, 'cp949');

  const schoolRaMatch = frameHtml.match(/url\s*:\s*'\s*\.\/([^']+)'/i);
  if (!schoolRaMatch) throw new Error('Failed to extract school search code path');
  comciganConfig.extractCode = `/${schoolRaMatch[1]}`;
  console.log('Extract Code Path:', comciganConfig.extractCode);

  const scDataIdx = frameHtml.indexOf("sc_data('");
  const subStr = frameHtml.substring(scDataIdx, scDataIdx + 60).replace(/\s+/g, '');
  const argMatch = subStr.match(/\((.*?)\)/);
  comciganConfig.scData = argMatch[1].split(',').map(s => s.replace(/['"]/g, ''));
  console.log('scData:', comciganConfig.scData);
}

function toCp949Hex(str) {
  const buf = iconv.encode(str, 'cp949');
  return Array.from(buf).map(b => '%' + b.toString(16).toUpperCase().padStart(2, '0')).join('');
}

function decodeBody(buffer) {
  const decodedUtf8 = iconv.decode(buffer, 'utf-8');
  if (decodedUtf8.includes('학교검색') || decodedUtf8.includes('자료') || decodedUtf8.includes('학교명')) {
    return decodedUtf8;
  }
  return iconv.decode(buffer, 'cp949');
}

function cleanJsonBody(rawText) {
  const start = rawText.indexOf('{');
  const end = rawText.lastIndexOf('}');
  if (start !== -1 && end !== -1) {
    return rawText.substring(start, end + 1);
  }
  return rawText;
}

async function run() {
  try {
    await initComcigan();
    const schoolCode = 44134; // 서울 양동중학교
    
    // Fetch raw timetable json
    const s7 = `${comciganConfig.scData[0]}${schoolCode}`;
    const payload = `${s7}_0_${comciganConfig.scData[2]}`;
    const base64Payload = Buffer.from(payload).toString('base64');
    
    const pathOnly = comciganConfig.extractCode.split('?')[0];
    const fetchUrl = `${comciganConfig.baseUrl}${pathOnly}?${base64Payload}`;
    console.log('Fetching Timetable URL:', fetchUrl);
    
    const res = await axios.get(fetchUrl, { responseType: 'arraybuffer', timeout: 7000 });
    const decoded = decodeBody(res.data);
    const cleaned = cleanJsonBody(decoded);
    const data = JSON.parse(cleaned);
    
    console.log('School Name:', data['학교명']);
    const teacherList = data['자료446'] || [];
    console.log('Teacher List (Total:', teacherList.length, '):');
    
    // Find any teacher containing '강' or '진'
    const matches = teacherList.filter(t => t && (t.includes('강') || t.includes('진') || t.includes('양')));
    console.log('Matching teachers with 강/진/양:', matches);
    
    const target = matches.find(t => t.includes('강진'));
    if (target) {
      console.log('Target string:', JSON.stringify(target));
      for (let i = 0; i < target.length; i++) {
        console.log(`char[${i}]:`, target.charCodeAt(i), JSON.stringify(target[i]));
      }
    }
  } catch (e) {
    console.error('Error occurred:', e);
  }
}

run();
