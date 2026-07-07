// State management
let selectedSchool = null;
let savedTimetableData = null;
let updateInterval = null;

// DOM Elements
const setupView = document.getElementById('setup-view');
const timetableView = document.getElementById('timetable-view');
const schoolSearchInput = document.getElementById('school-search-input');
const schoolSearchBtn = document.getElementById('school-search-btn');
const searchResultsContainer = document.getElementById('search-results-container');
const selectedSchoolStatus = document.getElementById('selected-school-status');
const teacherNameInput = document.getElementById('teacher-name-input');
const submitSetupBtn = document.getElementById('submit-setup-btn');

const activeSchoolInfo = document.getElementById('active-school-info');
const resetSetupBtn = document.getElementById('reset-setup-btn');
const timetableGridContainer = document.getElementById('timetable-grid-container');

const updateNotification = document.getElementById('update-notification');
const updateInstallBtn = document.getElementById('update-install-btn');

// App Initialization
document.addEventListener('DOMContentLoaded', async () => {
  // 1. Check for updates on start
  checkApplicationUpdates();

  // 2. Restore saved settings
  const savedSchool = localStorage.getItem('savedSchool');
  const savedTeacher = localStorage.getItem('savedTeacher');

  if (savedSchool && savedTeacher) {
    try {
      const school = JSON.parse(savedSchool);
      await loadTimetableAndSwitch(school.code, savedTeacher);
    } catch (e) {
      console.error('Failed to auto-load timetable:', e);
      localStorage.clear();
      switchToSetupView();
    }
  } else {
    switchToSetupView();
  }
});

// Event Listeners for Setup View
schoolSearchBtn.addEventListener('click', performSchoolSearch);
schoolSearchInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') performSchoolSearch();
});

submitSetupBtn.addEventListener('click', async () => {
  if (!selectedSchool) {
    alert('시간표를 생성할 학교를 검색하고 선택해 주세요.');
    return;
  }
  const teacherName = teacherNameInput.value.trim();
  if (teacherName.length < 2) {
    alert('교사 실명 약칭을 최소 2자 이상 입력해 주세요.');
    return;
  }

  submitSetupBtn.disabled = true;
  submitSetupBtn.innerHTML = '시간표 생성 중...';

  try {
    await loadTimetableAndSwitch(selectedSchool.code, teacherName);
    
    // Save settings
    localStorage.setItem('savedSchool', JSON.stringify(selectedSchool));
    localStorage.setItem('savedTeacher', teacherName);
  } catch (err) {
    alert(`시간표를 불러오는 데 실패했습니다:\n${err.message}`);
  } finally {
    submitSetupBtn.disabled = false;
    submitSetupBtn.innerHTML = '<span class="icon">✓</span> 시간표 생성 및 시작';
  }
});

resetSetupBtn.addEventListener('click', () => {
  if (confirm('설정을 초기화하고 처음 단계로 돌아가시겠습니까?')) {
    localStorage.clear();
    switchToSetupView();
  }
});

// Search schools via Electron main process Comcigan scraper
async function performSchoolSearch() {
  const keyword = schoolSearchInput.value.trim();
  if (keyword.length < 2) {
    alert('검색어를 2글자 이상 입력해 주세요.');
    return;
  }

  schoolSearchBtn.disabled = true;
  schoolSearchBtn.innerHTML = '검색 중...';
  searchResultsContainer.innerHTML = '';
  searchResultsContainer.classList.add('hidden');

  try {
    const list = await window.boardestAPI.searchSchool(keyword);
    if (list.length === 0) {
      searchResultsContainer.innerHTML = '<div class="result-item" style="color: rgba(255,255,255,0.4); text-align: center; cursor: default;">검색된 학교가 없습니다.</div>';
    } else {
      list.forEach(school => {
        const div = document.createElement('div');
        div.className = 'result-item';
        div.innerHTML = `<strong>${school.name}</strong> <span style="font-size: 11px; opacity: 0.5;">(${school.regionName})</span>`;
        div.addEventListener('click', () => {
          document.querySelectorAll('.result-item').forEach(el => el.classList.remove('selected'));
          div.classList.add('selected');
          selectSchool(school);
        });
        searchResultsContainer.appendChild(div);
      });
    }
    searchResultsContainer.classList.remove('hidden');
  } catch (err) {
    alert(`학교 검색 중 오류 발생: ${err.message}`);
  } finally {
    schoolSearchBtn.disabled = false;
    schoolSearchBtn.innerHTML = '<span class="icon">🔍</span> 검색';
  }
}

function selectSchool(school) {
  selectedSchool = school;
  selectedSchoolStatus.className = 'selected-status-box active';
  selectedSchoolStatus.innerText = `[${school.regionName}] ${school.name}`;
}

function switchToSetupView() {
  if (updateInterval) clearInterval(updateInterval);
  setupView.classList.add('active');
  timetableView.classList.remove('active');
  selectedSchool = null;
  selectedSchoolStatus.className = 'selected-status-box empty';
  selectedSchoolStatus.innerText = '지정된 학교 없음';
  schoolSearchInput.value = '';
  teacherNameInput.value = '';
  searchResultsContainer.innerHTML = '';
  searchResultsContainer.classList.add('hidden');
}

async function loadTimetableAndSwitch(schoolCode, teacherName) {
  const data = await window.boardestAPI.getTimetable(schoolCode, teacherName);
  savedTimetableData = data;

  activeSchoolInfo.innerText = `${data.schoolName} | ${teacherName} 선생님 시간표`;
  renderTimetable(data);

  setupView.classList.remove('active');
  timetableView.classList.add('active');

  // Start periodic highlighting
  if (updateInterval) clearInterval(updateInterval);
  highlightCurrentPeriod();
  updateInterval = setInterval(highlightCurrentPeriod, 10000); // 10초마다 갱신
}

// Render Weekly Timetable
function renderTimetable(data) {
  timetableGridContainer.innerHTML = '';

  const dayNames = ['월요일', '화요일', '수요일', '목요일', '금요일'];
  const dayEng = ['MON', 'TUE', 'WED', 'THU', 'FRI'];

  for (let day = 1; day <= 5; day++) {
    const col = document.createElement('div');
    col.className = 'timetable-col';
    col.id = `day-column-${day}`;

    // Col Header
    const colHeader = document.createElement('div');
    colHeader.className = 'col-header';
    colHeader.innerHTML = `<h3>${dayNames[day - 1]}</h3><div class="day-sub">${dayEng[day - 1]}</div>`;
    col.appendChild(colHeader);

    // Lessons container
    const lessonsContainer = document.createElement('div');
    lessonsContainer.className = 'lessons-container';

    // Loop 1 to 8 periods
    for (let period = 1; period <= 8; period++) {
      const lesson = data.weekly[day] ? data.weekly[day][period] : null;
      const card = document.createElement('div');
      card.id = `card-${day}-${period}`;

      if (lesson && lesson.subject) {
        card.className = 'lesson-card';
        card.innerHTML = `
          <div class="period-circle">${period}</div>
          <div class="lesson-details">
            <div class="subject-name">${lesson.subject}</div>
            <div class="class-info">
              <span>${lesson.className}</span>
              ${lesson.classroom ? `<span class="room-badge">${lesson.classroom}</span>` : ''}
            </div>
          </div>
        `;
      } else {
        card.className = 'lesson-card empty-slot';
        card.innerHTML = `
          <div class="period-circle">${period}</div>
          <div class="lesson-details">
            <div class="subject-name">수업 없음</div>
          </div>
        `;
      }
      lessonsContainer.appendChild(card);
    }
    col.appendChild(lessonsContainer);
    timetableGridContainer.appendChild(col);
  }
}

// Highlight Current Day & Current Period
function highlightCurrentPeriod() {
  if (!savedTimetableData) return;

  const now = new Date();
  const currentDay = now.getDay(); // 0=일 ~ 6=토
  const currentHour = now.getHours();
  const currentMin = now.getMinutes();
  const currentTimeVal = currentHour * 60 + currentMin; // Convert to minutes

  // 1. Remove all active highlighting
  document.querySelectorAll('.timetable-col').forEach(el => el.classList.remove('today'));
  document.querySelectorAll('.lesson-card').forEach(el => el.classList.remove('active-now'));

  // Weekend skip
  if (currentDay < 1 || currentDay > 5) return;

  // 2. Highlight today's column
  const todayCol = document.getElementById(`day-column-${currentDay}`);
  if (todayCol) todayCol.classList.add('today');

  // 3. Match period time
  // Default timetable standard periods (fallbacks if comcigan times fails or absent)
  // Typically Comcigan periodTimes is in format "HH:mm" (start time)
  // Let's parse comcigan periodTimes or use a default
  const periodTimes = savedTimetableData.periodTimes || [];
  
  let targetPeriod = -1;
  const lessonDuration = 45; // Default 45 mins
  
  if (periodTimes.length > 0) {
    for (let i = 0; i < periodTimes.length; i++) {
      const timeStr = periodTimes[i]; // e.g. "09:00"
      if (!timeStr) continue;

      const parts = timeStr.split(':');
      const startH = parseInt(parts[0], 10);
      const startM = parseInt(parts[1], 10);
      const startVal = startH * 60 + startM;
      const endVal = startVal + lessonDuration;

      if (currentTimeVal >= startVal && currentTimeVal < endVal) {
        // Comcigan indices could be offset by 1 or different, check mapping
        targetPeriod = i + 1; // 1-indexed period
        break;
      }
    }
  } else {
    // Standard default school periods fallback (e.g. 1st starts 09:00, etc.)
    const defaults = [
      { start: 540, end: 585 },  // 1교시: 09:00 ~ 09:45
      { start: 595, end: 640 },  // 2교시: 09:55 ~ 10:40
      { start: 650, end: 695 },  // 3교시: 10:50 ~ 11:35
      { start: 705, end: 750 },  // 4교시: 11:45 ~ 12:30
      { start: 800, end: 845 },  // 5교시: 13:20 ~ 14:05 (점심식사 후)
      { start: 855, end: 900 },  // 6교시: 14:15 ~ 15:00
      { start: 910, end: 955 },  // 7교시: 15:10 ~ 15:55
      { start: 965, end: 1010 }, // 8교시: 16:05 ~ 16:50
    ];
    for (let i = 0; i < defaults.length; i++) {
      if (currentTimeVal >= defaults[i].start && currentTimeVal < defaults[i].end) {
        targetPeriod = i + 1;
        break;
      }
    }
  }

  if (targetPeriod !== -1) {
    const activeCard = document.getElementById(`card-${currentDay}-${targetPeriod}`);
    if (activeCard) activeCard.classList.add('active-now');
  }
}

// Check Updates from GitHub Releases
async function checkApplicationUpdates() {
  try {
    const result = await window.boardestAPI.checkUpdate();
    if (result && result.hasUpdate && result.zipUrl) {
      updateNotification.classList.remove('hidden');
      updateInstallBtn.addEventListener('click', async () => {
        updateInstallBtn.disabled = true;
        updateInstallBtn.innerText = '업데이트 중...';
        try {
          await window.boardestAPI.performUpdate(result.zipUrl);
        } catch (e) {
          alert(`업데이트 에러: ${e.message}`);
          updateInstallBtn.disabled = false;
          updateInstallBtn.innerText = '업데이트 및 재시작';
        }
      });
    }
  } catch (e) {
    console.error('Update check failed:', e);
  }
}
