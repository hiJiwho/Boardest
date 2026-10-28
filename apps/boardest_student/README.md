# 🎒 Boardest Student — 개발자 & AI 협업 종합 가이드북

반갑습니다! 이 문서는 **Boardest Student(학생용 포털 웹 & 앱)**를 개발하는 **친구 개발자**와 **친구의 AI 어시스턴트(Cursor, Antigravity, Claude Code 등)**를 위한 전체 온보딩 및 구현 가이드입니다.

---

## 🏛️ 1. 프로젝트 비전 & 디바이스 환경

Boardest 생태계는 다음과 같이 3개의 축으로 구성됩니다:
* **교실 전자칠판 (`apps/boardest`)**: 수업 진행, 시간표, 칠판 판서, 급식 호출 수신
* **교사용 앱 (`apps/boardest_teacher`)**: 급식 호출 원격 제어, 학급 쪽지 전송, 수업 교안 관리
* **학생용 포털 (`apps/boardest_student`)**: **수행평가 캘린더, 시간표, 급식표, 우리 반 알림장, 개인 학습 도구**

### 💡 타겟 디바이스 핵심 고려사항 (중요!)
1. **학교 수업 시간**: 대부분의 초·중·고교에서 수업 중 스마트폰 사용이 제한됩니다.
   * 따라서 학교에서 보급된 **디벗 기기(크롬북, 웨일북, 교육청 안드로이드 태블릿, 웹 브라우저)**에서 별도 설치 없이 바로 구동되는 **Flutter Web & PWA 환경을 1순위로 지원**합니다.
2. **방과 후 / 가정**:
   * 학생 개인 스마트폰(안드로이드 APK 및 웹 링크)으로 접속하여 내일의 수행평가 과제와 급식 메뉴를 체크합니다.

---

## ⚡ 2. Firebase 할당량 초절약 원칙 (Firebase Quota Zero-Waste)

> [!CAUTION]
> **Cloud Firestore 주기적 쿼리 및 전체 스캔은 절대 금지됩니다.**  
> 수백 명의 학생이 5초마다 Firestore를 스캔하면 일일 무료 할당량이 순식간에 고갈되어 전국 교실 화면이 멈춥니다.

* **실시간 데이터는 100% Firebase Realtime Database (RTDB) 사용**:
  * RTDB 베이스 URL: `https://jiwhosboardest-default-rtdb.firebaseio.com/`
* **캐시 최우선 (Cache-First) 원칙**:
  * 앱을 켜면 `SharedPreferences`에 저장된 로컬 캐시를 먼저 0.01초 만에 화면에 띄우고, 백그라운드에서 RTDB를 1회 비동기 페치합니다.
* **주기적 타이머 금지**:
  * `Timer.periodic(Duration(seconds: 3), ...)` 같은 폴링 타이머를 만들지 마세요. 사용자의 명시적 '새로고침' 또는 앱 켤 때 1회 페치 방식을 권장합니다.

---

## 🚀 3. 빠른 로컬 개발 시작 (Day 1 시작하기)

```bash
# 1. 저장소 최신 코드 동기화
git pull origin main

# 2. 학생용 앱 디렉터리로 이동
cd apps/boardest_student

# 3. 의존성 패키지 설치
flutter pub get

# 4. 크롬 브라우저(학교 디벗 / 웹 환경)로 실행 (추천!)
flutter run -d chrome

# 5. 안드로이드 기기 또는 에뮬레이터로 실행
flutter run -d android
```

---

## 📡 4. 백엔드 데이터 통신 규격 (RTDB Schema)

### 4.1 수행평가 & 과제 데이터 (`/assessments`)
교실 전자칠판, 교사용 앱, 학생용 앱이 모두 동일한 RTDB 경로를 공유합니다:
* **엔드포인트**: `https://jiwhosboardest-default-rtdb.firebaseio.com/assessments/{schoolCode}/{grade}.json`
* **데이터 모델**:
```json
{
  "as_1730000000000": {
    "id": "as_1730000000000",
    "schoolCode": "ydm",
    "grade": 2,
    "classNum": 3,
    "subject": "수학",
    "title": "이차방정식 서술형 수행평가",
    "description": "교과서 45~52쪽 범위, 계산 과정 필수 작성",
    "dueDate": "2026-11-05T09:00:00.000Z",
    "type": "수행평가",
    "authorRole": "teacher",
    "authorName": "수학선생님",
    "createdAt": "2026-10-28T09:00:00.000Z"
  }
}
```
* **학생 개인 체크 상태**:
  * 학생이 "제출 완료"를 체크한 상태는 서버가 아닌 학생 기기의 `SharedPreferences`(`completed_assessments_${itemId}`)에 저장하여 프라이버시를 보호하고 서버 부하를 0으로 만듭니다.

### 4.2 급식 및 시간표 (교육부 NEIS Open API)
* 급식 식단표 및 일일 시간표는 Firebase를 거치지 않고 교육부 **NEIS Open API**를 직접 호출하므로 서버 비용이 전혀 들지 않습니다. (기존 `apps/boardest/lib/services/neis_service.dart`의 로직을 참고하세요!)

---

## 🛠️ 5. 단계별 기능 개발 로드맵

| 단계 | 기능명 | 구현 내용 및 가이드 |
|:---:|:---|:---|
| **Step 1** | **학생 프로필 & 학교 설정** | • 학교명/학교코드(NEIS) + 학년 + 반 설정<br>• 로컬 `SharedPreferences` 저장으로 재접속 시 자동 로그인 유지 |
| **Step 2** | **수행평가 캘린더 (`assessment_view.dart`)** | • RTDB에서 우리 학년/반 수행평가 목록 페치<br>• 마감 임박 순 정렬 및 `D-Day`, `D-2` 컬러 뱃지<br>• 학생 본인의 개인 과제 추가/삭제 기능<br>• 제출 완료 체크박스 토글 |
| **Step 3** | **오늘의 시간표 (`timetable_view.dart`)** | • NEIS API 또는 등록된 우리 반 일과 시간표 조회<br>• 현재 몇 교시인지 하이라이트 및 남은 쉬는 시간 카운트다운 |
| **Step 4** | **오늘의 급식표 (`meal_view.dart`)** | • 이번 주 식단 캘린더<br>• 알레르기 유발 식품(난류, 우유, 대두 등) 필터 및 강조 표시 |
| **Step 5** | **💡 친구만의 창의적 아이디어** | • 아래 AI 브레인스토밍 지침을 참고하여 자유롭게 기획/구현! |

---

## 🤖 6. 친구의 AI 에이전트를 위한 지침 (Prompt Template)

친구의 AI 에이전트(Cursor, Claude Code, Antigravity 등)에게 아래 내용을 프롬프트로 전달하세요:

```markdown
너는 Boardest Student (학생용 앱)의 메인 리드 엔지니어이자 기획 파트너야!
저장소 루트의 AGENT.md에 명시된 규칙을 반드시 준수해야 해:
1. Firestore 주기적 쿼리 절대 금지! 실시간 데이터는 RTDB(jiwhosboardest-default-rtdb.firebaseio.com) 사용.
2. 학생용 앱은 학교 디벗(크롬북/웹)과 스마트폰(앱) 모두에서 부드럽게 돌아가야 해.
3. Git 작업 시 main에 직접 커밋하지 말고 feature/student-* 브랜치를 사용해.

★ 특별 미션:
기본 기능(수행평가, 시간표, 급식, 알림장) 외에 "실제 학생들이 학교생활에서 매일 켜보고 싶어 할 만한 기발하고 창의적인 아이디어"를 친구에게 먼저 3가지 질문하고 의견을 모아봐!
(예: 학급 랜덤 롤링페이퍼, 급식 알레르기 푸시, 수업 집중 타이머, 익명 건의함, D-Day 위젯 등)
```

---

## 🌿 7. Git 브랜치 및 PR(Pull Request) 협업 규칙

1. **작업 시작 전 최신화**:
   ```bash
   git checkout main
   git pull origin main
   ```
2. **기능 브랜치 생성**:
   ```bash
   git checkout -b feature/student-assessment   # 예: 수행평가 기능 개발 시
   ```
3. **코드 작성 및 정적 분석 검사**:
   ```bash
   # 빌드하지 않고 문법 오류만 빠르게 검사
   dart analyze apps/boardest_student/lib/
   ```
4. **커밋 및 푸시**:
   ```bash
   git add .
   git commit -m "feat(student): implement assessment calendar and d-day badges"
   git push origin feature/student-assessment
   ```
5. **GitHub Pull Request 생성**:
   * GitHub 저장소에서 `feature/student-*` $\rightarrow$ `main` 브랜치로 PR을 올리면 메인 관리자(@hiJiwho)가 검토 후 머지합니다.
