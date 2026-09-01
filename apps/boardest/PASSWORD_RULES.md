# Boardest 자동 생성 계정 비밀번호 규칙 (Password Rules)

본 프로젝트에서는 교실 단말기(Flutter App) 및 급식 지도용 웹 매니저(web app)에서 비밀번호 입력란을 없애고 임시/자동 로그인을 수행하기 위해 고유한 비밀번호 생성 규칙을 활용하고 있습니다.

---

## 1. 교실 단말기 계정 (Class Account)

### A. 일반 교실 단말기 계정 (Standard Class Account - 비밀번호 있음)
* **계정 ID 포맷**: `Class.{학년}{반}@${학교명}.${지역명}.bst`
  * 예: `Class.201@길동중학교.서울.bst` (2학년 1반)
* **역할 및 권한**: 일반 학교 연동, 시간표 및 모든 판서 데이터 Read-Write 가능
* **비밀번호**: 회원가입 시 설정한 개별 비밀번호 (WPF 오버레이 등에서 입력 가능)

### B. 무비밀번호 급식 도우미 계정 (Passwordless Helper Account - 비밀번호 없음)
* **계정 ID 포맷**: `Class.{학년}{반}@${학교명}.${지역명}.NOPW.bst`
  * 예: `Class.201@길동중학교.서울.NOPW.bst` (2학년 1반)
* **역할 및 권한**: 급식 도우미 전용. 추후 급식 호출 상태(`eat_calls`) 컬렉션만 Read-Write 권한을 지니고, 나머지 모든 리소스는 Read-Only로 제한 처리됨
* **비밀번호 규칙**: `!Flutter-app@Class#acc${학년}%${반}^{학교명 영타}` (단말기 앱에서 자동 계산 및 입력 칸 생략)
  * 예 (`Class.201@길동중학교.서울.NOPW.bst` 일 때):
    * 학년: `2`
    * 반: `1`
    * 학교명 영타 (두벌식 매핑): `rlfehdwndgkrry`
    * 최종 비밀번호: `!Flutter-app@Class#acc$2%1^rlfehdwndgkrry`

---

## 2. 임시 급식지도 교사 계정 (Teacher Account)
* **계정 ID 포맷**: `Teacher.${교사명}@${학교명}.${지역명}.NOPW.bst`
  * 예: `Teacher.홍길동@길동중학교.서울.NOPW.bst`
* **비밀번호 규칙**: `!Temp@Teacher#acc${교사명 영타}%${학교명 영타}`
  * 예 (`Teacher.홍길동@길동중학교.서울.NOPW.bst` 일 때):
    * 교사명 영타: `ghdrlfehd`
    * 학교명 영타: `rlfehdwndgkrry`
    * 최종 비밀번호: `!Temp@Teacher#acc$ghdrlfehd%rlfehdwndgkrry`

---

## 3. 한글 자판 영타 변환 규칙 (Hangul-to-English Keyboard Mapping)
한글 문자를 완성형 단위에서 초성, 중성, 종성으로 분해한 후 두벌식 한글 자판에 대응하는 영문 키로 1:1 치환합니다.
* 예: `홍길동` -> `ㅎㅗㅇㄱㅣㄹㄷㅗㅇ` -> `g h d r l f e h d` -> `ghdrlfehd`
* 예: `길동중학교` -> `ㄱㅣㄹㄷㅗㅇㅈㅜㅇㅎㅏㄱㄱㅛ` -> `r l f e h d w n g h r r y` -> `rlfehdwndgkrry`
