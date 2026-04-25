# 시간표 분석 사이트 (GitHub Pages)

정적 웹앱으로 만든 시간표 분석기입니다.

## 기능
- CSV 업로드 / 직접 입력
- 총 수업 시간, 바쁜 요일, 공강 시간 계산
- 시간 충돌 및 짧은 이동 시간 경고
- 주간 시간표 테이블 시각화

## GitHub.io 배포 방법
1. 이 저장소를 GitHub에 push
2. GitHub 저장소 Settings → Pages
3. **Build and deployment**
   - Source: `Deploy from a branch`
   - Branch: `main`(또는 현재 브랜치) / root
4. 저장 후 몇 분 뒤 `https://<계정명>.github.io/<저장소명>/` 접속

## CSV 예시
```csv
과목,요일,시작,종료,강의실
자료구조,월,09:00,10:30,공301
운영체제,월,10:30,12:00,공205
```
