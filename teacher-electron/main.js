const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const axios = require('axios');
const iconv = require('iconv-lite');
const AdmZip = require('adm-zip');
const { exec } = require('child_process');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    backgroundColor: '#0F0E17',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  // mainWindow.webContents.openDevTools(); // 필요 시 활성화
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

// ==========================================
// Comcigan Scraping Service (Node.js Port)
// ==========================================
const DEFAULT_URL = 'http://xn--s39aj90b0nb2xw6xh.kr';
let comciganConfig = {
  baseUrl: null,
  extractCode: null,
  scData: null,
};

async function initComcigan() {
  if (comciganConfig.baseUrl && comciganConfig.extractCode && comciganConfig.scData) return;

  try {
    // 1. Fetch main landing page
    const res1 = await axios.get(DEFAULT_URL, { responseType: 'arraybuffer', timeout: 7000 });
    let html = iconv.decode(res1.data, 'utf-8');
    if (!html.includes('frame')) {
      html = iconv.decode(res1.data, 'euc-kr');
    }

    // Parse frame src
    const frameMatch = html.match(/<frame\s+[^>]*src=["']([^"']+)["']/i);
    if (!frameMatch) throw new Error('Failed to find frame source in landing page');

    const framePath = frameMatch[1];
    const resolvedUrl = new URL(framePath, DEFAULT_URL).toString();
    const frameUrlObj = new URL(resolvedUrl);
    comciganConfig.baseUrl = `${frameUrlObj.protocol}//${frameUrlObj.host}`;

    // 2. Fetch frame HTML in CP949
    const res2 = await axios.get(resolvedUrl, { responseType: 'arraybuffer', timeout: 7000 });
    const frameHtml = iconv.decode(res2.data, 'cp949');

    // Extract school search code path (e.g. url:'./36179?17384l')
    const schoolRaMatch = frameHtml.match(/url\s*:\s*'\s*\.\/([^']+)'/i);
    if (!schoolRaMatch) throw new Error('Failed to extract school search code path');
    comciganConfig.extractCode = `/${schoolRaMatch[1]}`;

    // Extract sc_data
    const scDataIdx = frameHtml.indexOf("sc_data('");
    if (scDataIdx === -1) throw new Error('Failed to locate sc_data init call');

    const subStr = frameHtml.substring(scDataIdx, scDataIdx + 60).replace(/\s+/g, '');
    const argMatch = subStr.match(/\((.*?)\)/);
    if (!argMatch) throw new Error('Failed to parse sc_data args');

    comciganConfig.scData = argMatch[1].split(',').map(s => s.replace(/['"]/g, ''));
  } catch (err) {
    console.error('Comcigan initialization error:', err);
    throw new Error(`컴시간 초기화 실패: ${err.message}`);
  }
}

// Convert string to cp949 url hex string
function toCp949Hex(str) {
  const buf = iconv.encode(str, 'cp949');
  return Array.from(buf).map(b => '%' + b.toString(16).toUpperCase().padStart(2, '0')).join('');
}

// Clean JSON body from Comcigan server
function cleanJsonBody(rawText) {
  // Comcigan API returns body prepended with random/corrupted characters sometimes.
  // Find first '{' and last '}'
  const start = rawText.indexOf('{');
  const end = rawText.lastIndexOf('}');
  if (start !== -1 && end !== -1) {
    return rawText.substring(start, end + 1);
  }
  return rawText;
}

ipcMain.handle('search-school', async (event, keyword) => {
  try {
    await initComcigan();
    const hexQuery = toCp949Hex(keyword);
    const searchUrl = `${comciganConfig.baseUrl}${comciganConfig.extractCode}${hexQuery}`;
    
    const res = await axios.get(searchUrl, { responseType: 'arraybuffer', timeout: 7000 });
    const decoded = iconv.decode(res.data, 'cp949');
    const cleaned = cleanJsonBody(decoded);
    const data = JSON.parse(cleaned);

    const rawList = data['학교검색'] || [];
    // rawList: [ [지역코드, 지역명, 학교코드, 학교명, 종류], ... ]
    return rawList.map(item => ({
      regionCode: item[0],
      regionName: item[1],
      code: item[2],
      name: item[3],
      type: item[4],
    }));
  } catch (err) {
    console.error('School search failed:', err);
    throw new Error(`학교 검색 에러: ${err.message}`);
  }
});

ipcMain.handle('get-timetable', async (event, schoolCode, teacherName) => {
  try {
    await initComcigan();
    
    // Fetch raw timetable json
    const s7 = `${comciganConfig.scData[0]}${schoolCode}`;
    const payload = `${s7}_0_${comciganConfig.scData[2]}`;
    const base64Payload = Buffer.from(payload).toString('base64');
    
    const pathOnly = comciganConfig.extractCode.split('?')[0];
    const fetchUrl = `${comciganConfig.baseUrl}${pathOnly}?${base64Payload}`;
    
    const res = await axios.get(fetchUrl, { responseType: 'arraybuffer', timeout: 7000 });
    const decoded = iconv.decode(res.data, 'cp949');
    const cleaned = cleanJsonBody(decoded);
    const data = JSON.parse(cleaned);

    // Parse metadata
    const schoolName = data['학교명'] || '';
    const periodTimes = data['일과시간'] || [];
    const rawClassCounts = data['학급수'] || [];
    const classCounts = {};
    for (let g = 1; g < rawClassCounts.length; g++) {
      classCounts[g] = rawClassCounts[g];
    }

    const teacherList = data['자료446'] || [];
    const subjectList = data['자료492'] || [];
    
    const rawDaily = data['자료147']; // [학년][학급][요일][교시]
    
    // Find teacher index
    const targetName = teacherName.replace(/\*/g, '').trim();
    let teacherIdx = -1;
    for (let i = 0; i < teacherList.length; i++) {
      if (teacherList[i] && teacherList[i].replace(/\*/g, '').trim() === targetName) {
        teacherIdx = i;
        break;
      }
    }

    if (teacherIdx === -1) {
      throw new Error(`입력하신 교사 약칭 '${targetName}'을 찾을 수 없습니다. (입력 시 컴시간 기준 정명 2글자를 대조해주세요)`);
    }

    // Build Weekly timetable for this teacher
    // We want a structure: weekly[weekday][period] -> { subject, className, classroom }
    const weeklyTimetable = {};
    for (let day = 1; day <= 5; day++) {
      weeklyTimetable[day] = {};
      for (let p = 1; p <= 8; p++) {
        weeklyTimetable[day][p] = null;
      }
    }

    // Walk through all lessons to find matches for this teacher
    for (let g = 1; g <= 3; g++) { // 1~3학년
      const numClasses = classCounts[g] || 0;
      for (let c = 1; c <= numClasses; c++) {
        for (let day = 1; day <= 5; day++) {
          for (let p = 1; p <= 8; p++) {
            // Comcigan value decoding
            // rawDaily[grade][classNum][day][period]
            let val = 0;
            try {
              if (rawDaily[g] && rawDaily[g][c] && rawDaily[g][c][day] && rawDaily[g][c][day][p]) {
                val = rawDaily[g][c][day][p];
              }
            } catch (_) {}

            if (val > 0) {
              // val: subjectIndex * 100 + teacherIndex
              // or vice versa depending on '분리' value.
              // Comcigan standard encoding:
              const bunri = data['분리'] || 100;
              const subIdx = Math.floor(val / bunri);
              const teaIdx = val % bunri;

              if (teaIdx === teacherIdx) {
                const subject = subjectList[subIdx] || '';
                // Get classroom if available
                let classroom = '';
                try {
                  const rawClassrooms = data['자료245'];
                  if (rawClassrooms && rawClassrooms[g] && rawClassrooms[g][c] && rawClassrooms[g][c][day] && rawClassrooms[g][c][day][p]) {
                    const roomIdx = rawClassrooms[g][c][day][p];
                    classroom = data['자료447'] ? (data['자료447'][roomIdx] || '') : '';
                  }
                } catch (_) {}

                weeklyTimetable[day][p] = {
                  subject: subject,
                  className: `${g}학년 ${c}반`,
                  classroom: classroom,
                };
              }
            }
          }
        }
      }
    }

    return {
      schoolName,
      periodTimes,
      weekly: weeklyTimetable,
    };
  } catch (err) {
    console.error('Timetable loading failed:', err);
    throw new Error(err.message);
  }
});

// ==========================================
// GitHub Auto-Updater (Electron side)
// ==========================================
const CURRENT_VERSION = '1.0.0';
const GITHUB_REPO = 'hiJiwho/Boardest';

ipcMain.handle('check-update', async () => {
  try {
    const url = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;
    const res = await axios.get(url, { timeout: 8000 });
    
    if (res.status !== 200) return { hasUpdate: false };

    const data = res.data;
    const tagName = data.tag_name || '';
    if (!tagName) return { hasUpdate: false };

    const serverVersion = tagName.replace(/[^0-9.]/g, ''); // "v1.0.1" -> "1.0.1"
    const hasUpdate = isNewerVersion(CURRENT_VERSION, serverVersion);
    
    let zipUrl = null;
    if (hasUpdate && data.assets) {
      const teacherZip = data.assets.find(asset => asset.name.includes('teacher'));
      if (teacherZip) {
        zipUrl = teacherZip.browser_download_url;
      }
    }

    return {
      hasUpdate,
      currentVersion: CURRENT_VERSION,
      latestVersion: serverVersion,
      zipUrl,
    };
  } catch (err) {
    console.error('GitHub update check failed:', err);
    return { hasUpdate: false };
  }
});

function isNewerVersion(current, server) {
  try {
    const currentParts = current.split('.').map(Number);
    const serverParts = server.split('.').map(Number);
    for (let i = 0; i < serverParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (serverParts[i] > currentParts[i]) return true;
      if (serverParts[i] < currentParts[i]) return false;
    }
  } catch (_) {}
  return false;
}

ipcMain.handle('perform-update', async (event, url) => {
  try {
    const tempDir = app.getPath('temp');
    const zipPath = path.join(tempDir, 'boardest_teacher_update.zip');
    const extractDir = path.join(tempDir, 'boardest_teacher_extracted');

    // 1. Download ZIP
    const response = await axios({
      method: 'GET',
      url: url,
      responseType: 'stream',
    });

    const writer = fs.createWriteStream(zipPath);
    response.data.pipe(writer);

    await new Promise((resolve, reject) => {
      writer.on('finish', resolve);
      writer.on('error', reject);
    });

    // 2. Extract ZIP
    if (fs.existsSync(extractDir)) {
      fs.rmSync(extractDir, { recursive: true, force: true });
    }
    fs.mkdirSync(extractDir, { recursive: true });

    const zip = new AdmZip(zipPath);
    zip.extractAllTo(extractDir, true);

    // 3. Write replacement batch file
    const currentExePath = process.execPath;
    const currentAppDir = path.dirname(currentExePath);
    const updaterBatPath = path.join(tempDir, 'boardest_teacher_updater.bat');

    const updaterContent = `
@echo off
title Boardest Teacher Updater
echo Waiting for Boardest Teacher to close...
timeout /t 2 /nobreak > nul
echo Copying new files to: "${currentAppDir}"
xcopy /y /e /q "${extractDir}\\*" "${currentAppDir}\\"
echo Restarting Boardest Teacher...
start "" "${currentExePath}"
echo Done. Cleaning up...
del "%~f0"
`;

    fs.writeFileSync(updaterBatPath, updaterContent);

    // 4. Run updater batch file and exit
    exec(`start "" "${updaterBatPath}"`, () => {
      app.quit();
    });

    return true;
  } catch (err) {
    console.error('Update extraction/application failed:', err);
    throw new Error(`자동 업데이트 수행 중 오류가 발생했습니다: ${err.message}`);
  }
});
