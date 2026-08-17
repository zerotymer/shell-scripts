#!/bin/sh
# =============================================================================
#
# requirements: date, mktemp, uuidgen, whiptail
# =============================================================================
set -eu
(set -o pipefail 2>/dev/null) && set -o pipefail

SCRIPT_NAME=$(basename -- "$0")
VERSION='0.0.1'
DRY_RUN=0
TMP_DIR=''
AGENTS='CLAUDE'
GATEWAY_URL='https://md-gw.zerotymer.net'
SKILLS_PATH='.skills'

log()   { printf '%s [%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$1" "$2" >&2; }
info()  { log INFO  "$1"; }
warn()  { log WARN  "$1"; }
error() { log ERROR "$1"; }
die()   { error "$1"; exit "${2:-1}"; }

cleanup() {
  code=$?
  trap - EXIT INT TERM HUP
  [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf -- "$TMP_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_cmd() {
  for cmd in "$@"; do
    command -v -- "$cmd" >/dev/null 2>&1 || die "필수 명령 없음: $cmd"
  done
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $*"; return 0; fi
  "$@"
}

# 기본 메뉴를 보여준다.
menu() {
    backtitle=''
    while true; do
        input=$(whiptail --title "메뉴" --backtitle "$backtitle" --notags \
            --menu "메뉴를 선택하세요." 16 60 8 \
            --ok-button "확인" \
            --cancel-button "종료" \
            "1" "지시서 경로 설정" \
            "2" "참조문서 경로 설정" \
            "3" "산출물 경로 설정" \
            "4" "스킬 경로 설정" \
            "5" "스킬 추가" \
            3>&1 1>&2 2>&3)

        case $input in
            1) menu_instructions ;;
            4) menu_references ;;
            2) menu_outputs ;;
            3) menu_skills ;;
            5) menu_skills_check ;;
            *) exit 0 ;;
        esac
    done
}

# 지시서 경로를 설정한다.
menu_instructions() {
    instructions_path='instructions'
    completed_path='instructions/completed'
    log_filename='instructions.log'

    instructions_path=$(whiptail --title "지시서 경로를 설정합니다." --backtitle "$backtitle" \
    --inputbox "지시서를 보관할 경로를 입력하세요." 10 60 $instructions_path \
    3>&1 1>&2 2>&3)

    completed_path=$(whiptail --title "지시서 경로를 설정합니다."  --backtitle "$backtitle" \
    --inputbox "완료된 지시서를 보관할 경로를 입력하세요." 10 60 $completed_path \
    3>&1 1>&2 2>&3)

    log_filename=$(whiptail --title "지시서 경로를 설정합니다."  --backtitle "$backtitle" \
    --inputbox "지시서 로그를 저장할 파일이름을 입력하세요." 10 60 $log_filename \
    3>&1 1>&2 2>&3)

    message=$(printf '%s\n\n%s\n%s\n%s' \
        "입력한 경로로 지시서를 저장하시겠습니까?" \
        "지시서 경로: $instructions_path" \
        "완료된 지시서 경로: $completed_path" \
        "로그 파일이름: $log_filename")

    whiptail --title "지시서 경로를 설정합니다." --backtitle "$backtitle" \
    --yesno "$message" 11 80 \
    3>&1 1>&2 2>&3

    case $? in
        0) set_instructions "$instructions_path" "$completed_path" "$log_filename"
           whiptail --title "지시서 경로를 설정합니다." --backtitle "$backtitle" \
           --msgbox "지시서 경로가 설정되었습니다." 10 60;;
        1) echo "저장 취소";;
        255) echo "취소";;
    esac

}

# instructions_path, completed_path, log_filename
set_instructions() {
    log_filepath="${instructions_path}/${log_filename}"

    mkdir -p "$instructions_path" "$completed_path"

    # 로그 파일 설정
    touch "$log_filepath"
    echo "# Instructions Log" >> "$log_filepath"
    echo "# format: uuid | title | timestamp | status" >> "$log_filepath"
    echo "$(uuidgen) | 초기설정예제 | $(date -u +"%Y-%m-%dT%H:%M:%S%z") | created" >> "$log_filepath"

    # 지침 파일 설정
    touch "$AGENTS.md"
    echo "## INSTRUCTIONS" >> "$AGENTS.md"
    echo "모든 구현 작업은 ${instructions_path}/ 경로에 저장된 지침을 기준으로 진행한다." >> "$AGENTS.md"
    echo "### 지침 파일 생성" >> "$AGENTS.md"
    echo "1. UUID 발급: \`uuidgen\`" >> "$AGENTS.md"
    echo "2. 지침 파일 생성: ${instructions_path}/{slug}.md 생성. frontmatter에 uuid, title, status, created 기록" >> "$AGENTS.md"
    echo "3. 로그 파일 생성 및 업데이트: ${log_filepath}에 {uuid} | {title} | {timestamp} | {status} 기록" >> "$AGENTS.md"
    echo "4. 모든 단계 완료시 ${log_filepath}에 {uuid} | {title} | {timestamp} | completed 기록, 사용된 지시서는 ${completed_path}로 이동" >> "$AGENTS.md"

    backtitle="지시서 경로 설정: ${instructions_path}"
}

# 참조문서 경로를 설정한다.
menu_references() {
    references_path='references'

    references_path=$(whiptail --title "참조 문서 경로를 설정합니다." --backtitle "$backtitle" \
    --inputbox "참조 문서를 보관할 경로를 입력하세요." 10 60 $references_path \
    3>&1 1>&2 2>&3)

    message=$(printf '%s\n\n%s\n%s\n%s' \
        "입력한 경로로 참조 문서를 저장하시겠습니까?" \
        "참조문서 경로: $references_path")

    whiptail --title "지시서 경로를 설정합니다." --backtitle "$backtitle" \
    --yesno "$message" 11 80 \
    3>&1 1>&2 2>&3

    case $? in
        0) set_references "$references_path"
           whiptail --title "참조 문서 경로를 설정합니다." --backtitle "$backtitle" \
           --msgbox "참조 문서 경로가 설정되었습니다." 10 60;;
        1) echo "저장 취소";;
        255) echo "취소";;
    esac

}

# references_path
set_references() {
    mkdir -p $references_path

    # 지침 파일 설정
    touch "$AGENTS.md"
    echo "## REFERENCES" >> "$AGENTS.md"
    echo "${references_path}/ 에 참조 가능한 문서가 저장됩니다." >> "$AGENTS.md"

    backtitle="참조 문서 경로 설정: ${references_path}"
}

# 스킬 경로를 지정한다.
menu_skills() {
    skills_path='.skills'

    skills_path=$(whiptail --title "스킬 경로를 설정합니다." --backtitle "$backtitle" \
    --inputbox "스킬을 보관할 경로를 입력하세요." 10 60 $skills_path \
    3>&1 1>&2 2>&3)

    message=$(printf '%s\n\n%s\n%s\n%s' \
        "입력한 경로로 스킬을 저장하시겠습니까?" \
        "스킬 경로: $skills_path")

    whiptail --title "스킬 경로를 설정합니다." --backtitle "$backtitle" \
    --yesno "$message" 11 80 \
    3>&1 1>&2 2>&3

    case $? in
        0) set_skills "$skills_path"
           whiptail --title "스킬 경로를 설정합니다." --backtitle "$backtitle" \
           --msgbox "스킬 경로가 설정되었습니다." 10 60;;
        1) echo "저장 취소";;
        255) echo "취소";;
    esac
}

# skills_path
set_skills() {
    mkdir -p $skills_path

    # .gitignore 설정
    # touch ".gitignore"
    # echo "# --- SKILLS ---" >> ".gitignore"
    # echo ".skills/" >> ".gitignore"

    # 지침 파일 설정
    touch "$AGENTS.md"
    echo "## LLM-WIKI SKILL" >> "$AGENTS.md"
    echo "${skills_path}에 스킬이 존재하며 Agent는 참고한다." >> "$AGENTS.md"

    touch "$skills_path/skill-list.md"
    echo "# SKILL LIST" >> "$skills_path/skill-list.md"
    echo "AGNET는 LLM WIKI 스킬에 대해 다음의 목록을 참조하며, 필요시 현재 페이지를 업데이트 한다." >> "$skills_path/skill-list.md"
    echo "현재 페이지는 wiki-skill-import 스킬과 매핑되어있다." >> "$skills_path/skill-list.md"
    echo "| UUID | 용도 |" >> "$skills_path/skill-list.md"
    echo "|------|------|" >> "$skills_path/skill-list.md"



    backtitle="스킬 경로 설정: ${skills_path}"
    SKILLS_PATH=$skills_path
}

# 산출물 경로를 지정한다.
menu_outputs() {
    outputs_path='.output'

    outputs_path=$(whiptail --title "산출물 경로를 설정합니다." --backtitle "$backtitle" \
    --inputbox "산출물을 보관할 경로를 입력하세요." 10 60 $outputs_path \
    3>&1 1>&2 2>&3)

    message=$(printf '%s\n\n%s\n%s\n%s' \
        "입력한 경로로 산출물을 저장하시겠습니까?" \
        "산출물 경로: $outputs_path")

    whiptail --title "산출물 경로를 설정합니다." --backtitle "$backtitle" \
    --yesno "$message" 11 80 \
    3>&1 1>&2 2>&3

    case $? in
        0) set_outputs "$outputs_path"
        whiptail --title "산출물 경로를 설정합니다." --backtitle "$backtitle" \
        --msgbox "산출물 경로가 설정되었습니다." 10 60;;
        1) echo "저장 취소";;
        255) echo "취소";;
    esac
}

# outputs_path
set_outputs() {
    mkdir -p $outputs_path

    # .gitignore 설정
    touch ".gitignore"
    echo "# --- OUTPUTS ---" >> ".gitignore"
    echo ".output/" >> ".gitignore"

    backtitle="산출물 경로 설정: ${outputs_path}"
}

# 스킬 선택
menu_skills_check() {
    skills=$(whiptail --title "스킬 선택" \
        --checklist "설치할 스킬을 선택하세요." 15 80 6 \
        "14cea96f-f1e2-461e-b9a7-96b5a6f63b67" "Wiki Skill Import" ON \
        "e03f48fb-3e00-41d7-b99d-c32854567d67" "Git 브랜치 가이드라인" ON \
        "5b33f658-5caa-4ac0-b711-d1fd6cfb57a9" "LLM Reference Registry" OFF \
        "e6274b24-2c08-4367-8859-b5a92bd98d59" "정적 목업 확인용 서버" OFF 3>&1 1>&2 2>&3)

    if [ -z "$skills" ]; then
        exit 1
    fi

    for skill in $skills; do
        skill=$(echo "$skill" | tr -d '"')

        case "$skill" in
            "14cea96f-f1e2-461e-b9a7-96b5a6f63b67") name="wiki_skill_import" uuid="14cea96f-f1e2-461e-b9a7-96b5a6f63b67" download_skill;;
            "e03f48fb-3e00-41d7-b99d-c32854567d67") name="git_branch_guidelines" uuid="e03f48fb-3e00-41d7-b99d-c32854567d67" download_skill;;
            "5b33f658-5caa-4ac0-b711-d1fd6cfb57a9") name="llm_reference_registry" uuid="5b33f658-5caa-4ac0-b711-d1fd6cfb57a9" download_skill;;
            "e6274b24-2c08-4367-8859-b5a92bd98d59") name="static_mock_server" uuid="e6274b24-2c08-4367-8859-b5a92bd98d59" download_skill;;
            *) die "알 수 없는 스킬: $skill" 2 ;;
        esac
    done
}


# uuid, name
download_skill() {
    path="${SKILLS_PATH}/${name}"
    mkdir -p "$path"
    url="$GATEWAY_URL/pages/download?type=skill&uuid=$uuid"

    curl -fJs "$url&locale=en&filename=SKILL.md" -o "${path}/SKILL.md"
    curl -fJs -# "$url&locale=ko&filename=SKILL_ko.md" -o "${path}/SKILL_ko.md"

    echo "| ${uuid} | ${name} |" >> "$SKILLS_PATH/skill-list.md"

}

main() {
  require_cmd date mktemp uuidgen whiptail
  menu
}

main "$@"
