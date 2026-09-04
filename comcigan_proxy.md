# 🌐 Boardest Comcigan Cloudflare Worker Proxy (`comcigan_proxy.md`)

> **서버 주소**: `https://comcigan.jiwho.workers.dev`  
> **기술 스택**: Cloudflare Workers, `cloudflare:sockets` (Raw TCP Sockets), `TextDecoder('euc-kr')`  
> **용도**: 브라우저 HTTPS 환경(PWA / Web App / HTML)에서 컴시간 서버(`comci.net:4082`) 직접 호출 시 발생하는 **CORS** 및 **Mixed Content** 보안 통제 회피 및 초고속 동적 프록시 파싱.

---

## 📌 1. 아키텍처 및 핵심 메커니즘 분석

### 1) 100% 동적 CP949(KS X 1001) 한글 매핑 테이블 생성 엔진
기존의 하드코딩된 한글 변환 테이블 문자열을 완전히 없애고, 자바스크립트의 `TextDecoder('euc-kr')` 표준 API를 활용하여 런타임 시 2,350자의 KS X 1001 완형성 한글 코드를 100% 동적으로 생성합니다.
- **바이트 루프**: `0xB0` ~ `0xC8` (행) × `0xA1` ~ `0xFE` (열)
- **URL 인코딩**: 1byte ASCII 문자(`<=0x7F`)는 `%XX` 처리, 한글 및 CP949 완형성 문자는 인덱스 계산(`Math.floor(idx / 94) + 0xB0`, `(idx % 94) + 0xA1`)을 통해 exact CP949 URL hex 문자열(`%b1%b2`)을 구성합니다.

### 2) Direct Raw TCP Sockets (`cloudflare:sockets`)
HTTP 통신 대신 Cloudflare 엣지 인프라의 `connect({ hostname: 'comci.net', port: 4082 })` API를 통해 컴시간 전용 TCP 소켓에 직접 커넥션을 형성합니다.
- HTTP Request 헤더(`GET ... HTTP/1.1\r\nHost: comci.net:4082\r\n...`) 직접 송신
- 응답 버퍼에서 HTTP 헤더 종단(`\r\n\r\n` = `13, 10, 13, 10`)을 탐색하여 pure payload 바이트 배열 추출

### 3) 컴시간 동적 경로 & 추출 접두사 실시간 자동 감지 (`resolveComciganPath`)
컴시간 서버의 난독화된 JS 내부 경로가 주기적으로 업데이트되더라도 소스 수정 없이 실시간 감지합니다.
- `/st` 경로를 TCP 수신 ➔ `url:'./...'` 정규식 추적 ➔ extraction path (예: `/36179?17384l`) 업데이트
- `sc_data('73629_'...)` 구문 분석 ➔ 최신 `scPrefix` 자동 갱신

---

## 🚀 2. API 엔드포인트 사양 (API Endpoints)

### 1) 학교 검색 API (`/api/comcigan/search` 또는 `/search`)
키워드(학교명)를 전달받아 컴시간 등록 학교 목록을 검색합니다.

- **Request**:
  - `GET https://comcigan.jiwho.workers.dev/api/comcigan/search?school=양동중`
  - `GET https://comcigan.jiwho.workers.dev/search?q=양동중`
- **Response (200 OK)**:
  ```json
  {
    "status": "success",
    "query": "양동중",
    "schools": [
      {
        "regionCode": 11,
        "region": "서울",
        "name": "양동중학교",
        "code": 78625
      }
    ]
  }
  ```

### 2) 학교 시간표 & 교사 데이터 파싱 API (`/api/comcigan/lookup` 또는 `/lookup`)
5자리 학교 코드를 전달받아 전체 일과시간, 교사 목록 및 컴시간 원본 JSON 데이터를 추출합니다.

- **Request**:
  - `GET https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=78625`
  - `GET https://comcigan.jiwho.workers.dev/lookup?schoolCode=78625`
- **Response (200 OK)**:
  ```json
  {
    "status": "success",
    "code": "78625",
    "data": {
      "schoolName": "양동중학교",
      "teachers": [
        { "id": "홍길", "name": "홍길동" },
        { "id": "김수", "name": "김수학" }
      ],
      "rawJson": {
        "학교명": "양동중학교",
        "자료147": [ ... ],
        "자료481": [ ... ],
        "자료446": [ ... ],
        "자료492": [ ... ]
      }
    }
  }
  ```

---

## 💻 3. 클라이언트 연동 코드 예시 (Usage Code Snippets)

### 1) Flutter (Dart - Web Platform `kIsWeb`)
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> fetchTimetableWeb(int schoolCode) async {
  final url = Uri.parse('https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=$schoolCode');
  final response = await http.get(url);
  if (response.statusCode == 200) {
    final jsonMap = json.decode(utf8.decode(response.bodyBytes));
    return Map<String, dynamic>.from(jsonMap['data']['rawJson']);
  }
  throw Exception('Worker lookup error: ${response.statusCode}');
}
```

### 2) Vanilla JavaScript (HTML / Browser)
```javascript
// 1. 학교 검색
async function searchSchool(keyword) {
  const res = await fetch(`https://comcigan.jiwho.workers.dev/api/comcigan/search?school=${encodeURIComponent(keyword)}`);
  const data = await res.json();
  console.log(data.schools); // [{ region, name, code }, ...]
}

// 2. 시간표 & 원본 JSON 로드
async function loadSchoolData(schoolCode) {
  const res = await fetch(`https://comcigan.jiwho.workers.dev/api/comcigan/lookup?code=${schoolCode}`);
  const { data } = await res.json();
  console.log('학교명:', data.schoolName);
  console.log('교사목록:', data.teachers);
  console.log('원본JSON:', data.rawJson);
}
```

---

## 🔒 4. 보안 & CORS 정책
- `Access-Control-Allow-Origin: *` 가 기본 설정되어 모든 Web 도메인 및 PWA 호스트에서 제한 없이 호출할 수 있습니다.
- SSL/TLS (`https://`) 가 적용되어 Mixed-Content 차단을 완전 해소합니다.
