import sys
import json
import urllib.request
import urllib.parse
import re

school_name = sys.argv[1] if len(sys.argv) > 1 else "양동중"

print(f'🔍 [Comcigan Python CLI] 컴시간 서버 접속 및 학교 검색 중: "{school_name}"...')

landing_url = 'http://xn--s39aj90b0nb2xw6xh.kr'

try:
    # 1. Fetch Landing Page
    req = urllib.request.Request(landing_url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        landing_html = resp.read().decode('utf-8', errors='ignore')

    frame_match = re.search(r'''<frame\s+[^>]*src=["']([^"']+)["']''', landingHtml if 'landingHtml' in locals() else landing_html, re.I)
    if not frame_match:
        raise Exception("컴시간 프레임 URL 추출 실패")

    frame_url = urllib.parse.urljoin(landing_url, frame_match.group(1))
    parsed_frame = urllib.parse.urlparse(frame_url)
    base_url = f"{parsed_frame.scheme}://{parsed_frame.netloc}"

    # 2. Fetch Frame HTML
    req_frame = urllib.request.Request(frame_url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req_frame) as resp_frame:
        frame_html = resp_frame.read().decode('utf-8', errors='ignore')

    search_path_match = re.search(r'''url\s*:\s*'\s*\.\/([^']+)' ''', frame_html, re.I)
    if not search_path_match:
        raise Exception("컴시간 검색 경로 추출 실패")

    extract_code = '/' + search_path_match.group(1).strip()

    # 3. CP949 URL Encode query
    cp949_bytes = school_name.encode('euc-kr', errors='ignore')
    hex_query = ''.join([f"%{b:02x}" for b in cp949_bytes])

    search_url = base_url + extract_code + hex_query

    # 4. Query Comcigan Search Endpoint
    req_search = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req_search) as resp_search:
        result_text = resp_search.read().decode('utf-8', errors='ignore')

    clean_json = result_text[:result_text.rfind('}') + 1]
    data = json.loads(clean_json)
    school_list = data.get('학교검색', [])

    print(f"\n✅ [Comcigan Python CLI] 검색 성공! (서버: {base_url})")
    print(f"총 {len(school_list)}건 검색 결과:")
    print("==================================================")
    for idx, item in enumerate(school_list, 1):
        print(f"{idx}. [지역: {item[1]}] {item[2]} ➔ 학교코드: \033[36m{item[3]}\033[0m")
    print("==================================================\n")

except Exception as e:
    print(f"❌ 검색 오류 발생: {e}")
