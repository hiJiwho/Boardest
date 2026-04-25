const DAY_ORDER = ['월', '화', '수', '목', '금', '토', '일'];

const csvFile = document.getElementById('csvFile');
const rawInput = document.getElementById('rawInput');
const loadSample = document.getElementById('loadSample');
const analyzeBtn = document.getElementById('analyzeBtn');

const summarySection = document.getElementById('summarySection');
const issueSection = document.getElementById('issueSection');
const tableSection = document.getElementById('tableSection');
const summaryCards = document.getElementById('summaryCards');
const issues = document.getElementById('issues');
const timetable = document.getElementById('timetable');

const sampleCsv = `과목,요일,시작,종료,강의실
자료구조,월,09:00,10:30,공301
운영체제,월,10:30,12:00,공205
캡스톤디자인,화,13:00,15:30,창의관
데이터베이스,수,09:00,10:30,공402
인공지능,수,10:00,11:30,공110
컴퓨터네트워크,목,14:00,15:30,공301
알고리즘,금,09:00,10:30,공205`;

loadSample.addEventListener('click', () => {
  rawInput.value = sampleCsv;
});

csvFile.addEventListener('change', async (event) => {
  const [file] = event.target.files;
  if (!file) {
    return;
  }
  rawInput.value = await file.text();
});

analyzeBtn.addEventListener('click', () => {
  const entries = parseCsv(rawInput.value);
  if (!entries.length) {
    alert('유효한 수업 데이터가 없습니다. 헤더 포함 CSV를 확인해주세요.');
    return;
  }
  const normalized = entries
    .map(normalizeEntry)
    .filter((entry) => entry && DAY_ORDER.includes(entry.day));

  if (!normalized.length) {
    alert('요일/시간 형식이 맞는 데이터가 없습니다.');
    return;
  }

  renderSummary(normalized);
  renderIssues(normalized);
  renderTimetable(normalized);

  summarySection.hidden = false;
  issueSection.hidden = false;
  tableSection.hidden = false;
});

function parseCsv(text) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length < 2) {
    return [];
  }

  const headers = lines[0].split(',').map((h) => h.trim());
  const findIdx = (names) => headers.findIndex((h) => names.includes(h));

  const subjectIdx = findIdx(['과목', 'subject']);
  const dayIdx = findIdx(['요일', 'day']);
  const startIdx = findIdx(['시작', 'start']);
  const endIdx = findIdx(['종료', 'end']);
  const roomIdx = findIdx(['강의실', 'room']);

  if ([subjectIdx, dayIdx, startIdx, endIdx].some((idx) => idx < 0)) {
    return [];
  }

  return lines.slice(1).map((line) => {
    const cols = line.split(',').map((c) => c.trim());
    return {
      subject: cols[subjectIdx] || '',
      day: cols[dayIdx] || '',
      start: cols[startIdx] || '',
      end: cols[endIdx] || '',
      room: roomIdx >= 0 ? cols[roomIdx] || '' : '-',
    };
  });
}

function normalizeEntry(entry) {
  const dayMap = {
    월요일: '월',
    화요일: '화',
    수요일: '수',
    목요일: '목',
    금요일: '금',
    토요일: '토',
    일요일: '일',
  };
  const day = dayMap[entry.day] || entry.day;
  const startMin = toMinutes(entry.start);
  const endMin = toMinutes(entry.end);

  if (Number.isNaN(startMin) || Number.isNaN(endMin) || endMin <= startMin) {
    return null;
  }

  return {
    ...entry,
    day,
    startMin,
    endMin,
    duration: endMin - startMin,
  };
}

function toMinutes(time) {
  const [hh, mm] = time.split(':').map(Number);
  return hh * 60 + mm;
}

function renderSummary(items) {
  const totalMinutes = items.reduce((sum, c) => sum + c.duration, 0);
  const daysUsed = new Set(items.map((c) => c.day));
  const dayBuckets = bucketByDay(items);
  const busiest = Object.entries(dayBuckets)
    .map(([day, arr]) => ({ day, mins: arr.reduce((s, c) => s + c.duration, 0) }))
    .sort((a, b) => b.mins - a.mins)[0];

  const gapMinutes = Object.values(dayBuckets)
    .map((arr) => {
      const sorted = [...arr].sort((a, b) => a.startMin - b.startMin);
      let gaps = 0;
      for (let i = 1; i < sorted.length; i += 1) {
        const gap = sorted[i].startMin - sorted[i - 1].endMin;
        if (gap > 0) {
          gaps += gap;
        }
      }
      return gaps;
    })
    .reduce((a, b) => a + b, 0);

  const cards = [
    { label: '총 수업 수', value: `${items.length}개` },
    { label: '총 수업 시간', value: `${(totalMinutes / 60).toFixed(1)}시간` },
    { label: '수업 있는 요일', value: `${daysUsed.size}일` },
    {
      label: '가장 바쁜 요일',
      value: busiest ? `${busiest.day} (${(busiest.mins / 60).toFixed(1)}h)` : '-',
    },
    { label: '공강(이동 포함) 시간', value: `${(gapMinutes / 60).toFixed(1)}시간` },
  ];

  summaryCards.innerHTML = cards
    .map(
      (card) => `
      <article class="metric">
        <div class="label">${card.label}</div>
        <div class="value">${card.value}</div>
      </article>
    `
    )
    .join('');
}

function renderIssues(items) {
  const dayBuckets = bucketByDay(items);
  const messages = [];

  Object.entries(dayBuckets).forEach(([day, lectures]) => {
    const sorted = [...lectures].sort((a, b) => a.startMin - b.startMin);

    for (let i = 1; i < sorted.length; i += 1) {
      const prev = sorted[i - 1];
      const cur = sorted[i];

      if (cur.startMin < prev.endMin) {
        messages.push({
          cls: 'danger',
          text: `[${day}] ${prev.subject} 와(과) ${cur.subject} 시간이 겹칩니다.`,
        });
      }

      const moveGap = cur.startMin - prev.endMin;
      if (moveGap >= 0 && moveGap < 10) {
        messages.push({
          cls: 'warn',
          text: `[${day}] ${prev.subject} → ${cur.subject} 사이 이동 시간이 ${moveGap}분입니다.`,
        });
      }
    }
  });

  if (!messages.length) {
    messages.push({ cls: 'ok', text: '충돌 또는 촉박한 이동 시간이 발견되지 않았습니다.' });
  }

  issues.innerHTML = messages.map((m) => `<li class="${m.cls}">${m.text}</li>`).join('');
}

function renderTimetable(items) {
  const startHour = 8;
  const endHour = 21;
  const weekdays = DAY_ORDER.slice(0, 5);

  const byDay = bucketByDay(items);

  let html = '<thead><tr><th>시간</th>';
  weekdays.forEach((d) => {
    html += `<th>${d}</th>`;
  });
  html += '</tr></thead><tbody>';

  for (let hour = startHour; hour < endHour; hour += 1) {
    html += `<tr><th>${String(hour).padStart(2, '0')}:00</th>`;

    weekdays.forEach((day) => {
      const blocks = (byDay[day] || [])
        .filter((c) => c.startMin < (hour + 1) * 60 && c.endMin > hour * 60)
        .map(
          (c) =>
            `<div class="block"><strong>${c.subject}</strong><small>${c.start}~${c.end} · ${c.room}</small></div>`
        )
        .join('');

      html += `<td>${blocks}</td>`;
    });

    html += '</tr>';
  }

  html += '</tbody>';
  timetable.innerHTML = html;
}

function bucketByDay(items) {
  return items.reduce((acc, c) => {
    acc[c.day] = acc[c.day] || [];
    acc[c.day].push(c);
    return acc;
  }, {});
}
