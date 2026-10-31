# 🚀 Boardest v5.4.3 Official Release

## ✨ 주요 개선 사항 (v5.4.3)
- **수행평가(Performance Assessment) 전면 재구축**:
  - `Boardest Teacher`: 선택된 학년의 **1반 ~ 12반** 전체 표시 및 학교 내 실제 설치된 반 자동 감지 (미설치 반 비활성화 처리)
  - 교사 앱에서 등록한 수행평가가 대상 반 교실(`Boardest Class`)에 즉시 동기화 및 표시
  - 교실(`Boardest Class`)에서 등록한 수행평가는 해당 학년·반에만 표시되도록 격리 및 학교 코드 정규화
- **TBP & Canva 스마트 보드 뷰어 개선**:
  - 16:9 컨테이너 및 `1536x864` 기준 배율(`sync1536Scale`) 동기화로 전자저작물(`국어 2-2` 등) 잘림 현상 해결
  - Canva 및 TBP 페이지 이동 후 이전 페이지로 돌아올 때 판서(Ink)가 유지되도록 페이지 ID 정규화 및 실시간 자동 저장 적용
  - 우측 상단 입력 모드를 **Pen (기본)** / **Touch** 2종으로 단순화
- **PowerPoint 오버레이 판서 (`boardest_ppt_overlay.exe`) 안정화**:
  - `0x80010001 (RPC_E_CALL_REJECTED)` COM 호출 거부 자동 재시도 필터(`IOleMessageFilter`) 적용 및 에러 팝업 제거
  - 주 모니터 해상도 기준 하단 독 툴바 표시 및 슬라이드 쇼 자동 재연결 지원
- **자동 업데이트 및 시작 메뉴 등록 개선**:
  - `Boardest Class` 윈도우 자동 업데이트 시 `.msix` 패키지를 정확히 다운로드하여 설치하도록 수정
  - `Boardest Teacher` 설치 시 Windows 시작 메뉴(앱 서랍) 루트 및 프로그램 목록에 즉시 등록되도록 개선
