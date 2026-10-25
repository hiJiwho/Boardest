### Boardest v5.0.12 Release Notes
- **3대 전용 루트 폴더 체계 일원화**: Google Drive 최상위에 `bst-save`(일반/껍데기), `bst-tbp`(교과서/웹교안 실체), `bst-pen`(판서 데이터) 3대 폴더로 통합 및 정리
- **32자리 고유 ID 기반 포인터 껍데기(Pointer Shell) 아키텍처**: TBP/HTMLP 생성 시 32자리 무작위 hex ID 발급, `bst-tbp/{id}`에 원본 보관, `bst-save`에는 경량 껍데기 JSON(`.tbp`/`.htmlp`)을 배치하여 자유로운 폴더 이동/정리 지원
- **안전한 연쇄 삭제(Cascade Delete)**: 껍데기 삭제 전 반드시 경고 확인창 노출 및 확인 시 `bst-tbp/{id}`와 `bst-pen/{id}` 실체 동시 영구 삭제
- **비밀번호 암호화 백업 및 자동 복원**: `boardest1217` 비밀번호 암호화 압축(`.tbp.save`/`.htmlp.save`) 다운로드 및 파일 업로드 시 자동 압축 해제 및 신규 ID 발급 복원 지원
- **교실 앱 Cloud 연동 필수화**: 클라우드 미연결 시 간편 OTP/QR 안내 및 `bst-save` 껍데기 탐색을 통한 TBP/HTMLP 로드 지원
- **앱 헤더 버전 표기**: `BOARDEST V.5.0.12` 일괄 판올림
