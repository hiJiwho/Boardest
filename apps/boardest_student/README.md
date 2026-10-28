# 🎒 Boardest Student (학생용 포털 웹 & 앱)

Boardest 생태계의 학생 전용 서비스로, **학교 디벗(크롬북/웨일북/태블릿)** 및 **개인 스마트폰**에서 수행평가, 시간표, 급식표, 우리 반 알림장을 한눈에 확인하고 교실과 소통하는 클라이언트입니다.

---

## 🚀 빠른 시작 (로컬 실행 가이드)

친구는 이 디렉터리(`apps/boardest_student`)에서 바로 개발 및 테스트를 시작할 수 있습니다!

```bash
# 1. 패키지 의존성 설치
cd apps/boardest_student
flutter pub get

# 2. 크롬 브라우저(학교 디벗 / 웹 환경)로 실행
flutter run -d chrome

# 3. 안드로이드 기기 또는 에뮬레이터로 실행
flutter run -d android
```

---

## 🛠️ 구현 우선순위 및 가이드

1. **수행평가 캘린더 (`lib/views/assessment_view.dart`)**:
   * Firebase RTDB `https://jiwhosboardest-default-rtdb.firebaseio.com/assessments/$schoolCode/$grade.json` 연동
   * D-Day 계산 및 마감 임박 알림 뱃지
   * 학생 개인별 체크박스 (제출 완료 / 미완료 상태 로컬 저장)
2. **오늘의 시간표 (`lib/views/timetable_view.dart`)**:
   * NEIS Open API 또는 로컬 설정 기반 일일 시간표 뷰어
   * 현재 교시 하이라이트 및 쉬는 시간 안내
3. **급식표 (`lib/views/meal_view.dart`)**:
   * 일주일 급식 메뉴 및 영양정보/알레르기 표시
4. **학생 아이디어 영역**:
   * 친구와 친구 AI가 자유롭게 브레인스토밍하여 추가 기능을 제안하고 구현해보세요!

---

## ⚠️ 필수 개발 수칙 (AGENT.md 준수)
* **Firestore 주기적 쿼리 절대 금지**: 실시간 데이터는 무조건 RTDB(`jiwhosboardest-default-rtdb.firebaseio.com`) 또는 SSE 스트림을 사용합니다.
* **Git 브랜치**: `feature/student-기능명` 브랜치에서 작업 후 GitHub Pull Request(PR)를 생성해 주세요.
