# Original User Request

## Parameters
[skip-interview]
How this run was launched; not part of the task.

## Initial Request — 2026-11-01T08:56:14Z

사용자의 명시적인 사전 지시("이제 묻지 말고 알아서 잘 나눠서 문제점 분석 후 수정해줘")에 따라 인터뷰 과정을 생략하고 즉시 실행으로 전환합니다. 

요구사항:
1. Class 앱 QR Cloud 접속 실패 문제 해결 (QR 대상 URL 및 라우팅 파라미터, Cloud 웹/앱 리디렉션 정합성 검증)
2. Android 환경에서 앱 업데이트 완료 후에도 계속 '업데이트 필요' 알림/잠금이 발생하는 무한 루프 버그 수정 (update_service.dart의 PackageInfo 버전 파싱, 버전 문자열 비교 로직, GitHub Releases 태그 파싱 불일치 해결)
3. 전체 생태계 v5.5.0 (5.5.0+5500) 버전 일괄 동기화 및 25개 컴포넌트 무결성 검증, 빌드 및 배포 완료

즉시 병렬 트랙 분석 및 구현을 시작해 주세요.

## Follow-up — 2026-11-01T09:10:56Z

[사용자 Grill-me 인터뷰 100% 합의 완료 및 실행 지침]

1. [QR Cloud 접속 복구]:
   - `database.rules.json`에 `cloud_pair_sessions` 보안 규칙(".read": true, ".write": true)을 즉시 추가하고 Firebase RTDB 규칙 배포.
   - 스마트폰 브라우저에서 `boardest-cloud-connect.web.app` 로그인 시 RTDB `cloud_pair_sessions/${reversePairSecret}.json`에 무기록(Zero-Persistence) 1회성 토큰 전달 및 전자칠판 즉시 수신/연결 보장.

2. [Android 업데이트 루프 원천 차단]:
   - Android `MainActivity.kt`에 `getAppVersion` / `getPackageInfo` MethodChannel 메서드 추가하여 실제 설치된 APK의 `versionName`(`5.5.0`) 반환.
   - `update_service.dart`의 `initVersion()`에서 Android일 때 MethodChannel을 통해 실제 `versionName`을 읽어 `_resolvedVersion`에 캐싱하도록 구현.
   - `apps/boardest/assets/version.json` 및 `pubspec.yaml` 버전을 `5.5.0+5500`으로 완전 동기화.

3. [v5.5.0 대규모 릴리즈 확정]:
   - 버전: `5.5.0+5500` (Class, Teacher, Cloud, Class Lite, Teacher Lite 전체 일괄 동기화)
   - C# 인스톨러, 빌드 스크립트, 웹 사이트, 25개 컴포넌트(C01~C25) E2E 검증 통과 후 빌드 및 배포 마무리.

위 3개 합의 사항에 따라 즉시 구현 및 빌드/배포를 완료해 주세요.
