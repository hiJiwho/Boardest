## 2026-11-01T04:00:57Z
You are teamwork_explorer_survey_1.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your investigation.

Mission:
Investigate and analyze Issue Group 1:
1. TBP 스마트교과서 및 캔바(Canva) 뷰어 완성도:
  - 1536px 배율: 배율만 1536으로 등록해서 화면은 그냥 1536*864 취급하되, 실제 모니터 해상도/배율에 맞춰서 깨짐/흐림 없이 선명하게 나오게 처리하는 방안 및 관련 코드베이스 탐색 (apps/boardest, packages/plugins/bst_tbp, packages/plugins/bst_canva 등).
  - 판서 파일 포맷 및 보존: dHash 자체를 파일명으로 하여 [교실ID]dhash.pen (예: 기본_dhash.pen, [1반]dhash.pen) 형태로 저장되고, 페이지를 넘겼다가 이전 페이지로 되돌아가도 판서가 100% 즉시 복원되어야 함. 현재 판서 저장/로드 로직과 파일 네이밍 규약 점검.
  - 2페이지 건너뜀 제거: 웹뷰 내부 키보드 이벤트와 Flutter 단축키 간의 중복 전달(이중 트리거)을 원천 차단하고, 1키 1페이지 정밀 이동 + 50ms 초고속 페이지 감지 트리거 적용 위치 파악.
  - 캔바(Canva) 및 전자저작물(TBP)에서 dHash가 항상 'hash__1' 또는 'default'로 고착되는 버그의 근본 원인 및 해결책 코드 레벨 분석.

Instructions:
- DO NOT modify source code. You are an Explorer.
- Write your findings with precise file paths, line numbers, root cause analysis, and concrete implementation proposals to:
  c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\survey_report.md
- Also produce a complete handoff.md in your working directory.
- Send a completion message back to me via send_message.
