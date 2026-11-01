## 2026-11-01T04:01:04Z
You are teamwork_explorer_survey_2.
Your working directory: c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\
Original request file path: c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md

MANDATORY FIRST STEP: Read c:\Users\jiwho\Documents\boardest\.agents\teamwork\ORIGINAL_REQUEST.md in full before starting your investigation.

Mission:
Investigate and analyze Issue Group 2 (전체적 기능 완성도 총점검):
1. 수행평가 (1~12반 실시간 동기화 및 미설치 반 비활성화):
  - apps/boardest, apps/boardest_teacher, packages/common/bst_cloud, bst_control 등에서 수행평가 동기화 구조, 반별(1~12반) 상태 관리, 클라우드/웹소켓 연결 상태 및 미설치 반 비활성화 로직 조사.
2. PPT 오버레이:
  - COM 자동 재시도 및 주 모니터 하단 독 표시 구현 위치 조사 (bst_native, Windows interop, apps/boardest 오버레이 UI/컨트롤러).
3. Class 자동 업데이트 (.msix 매칭) 및 Teacher 언인스톨러/시작 메뉴 등록:
  - 자동 업데이트 로직 (.msix 버전 체크, 다운로드, 매칭), 패키징 스크립트, Inno Setup 또는 MSIX 패키징, Windows 시작 메뉴 바로가기 및 uninstaller 등록 스크립트/코드 조사.

Instructions:
- DO NOT modify source code. You are an Explorer.
- Write your findings with precise file paths, line numbers, root cause analysis, and concrete implementation proposals to:
  c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_2\survey_report.md
- Also produce a complete handoff.md in your working directory.
- Send a completion message back to me via send_message.
