#!/usr/bin/env bash
set -uo pipefail

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
CYN='\033[0;36m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

ok()   { echo -e "  ${GRN}✓${RST} $*"; }
fail() { echo -e "  ${RED}✗${RST} $*"; }
warn() { echo -e "  ${YLW}!${RST} $*"; }
info() { echo -e "  ${CYN}i${RST} $*"; }

check_deps() {
    local missing=()
    for cmd in curl jq git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing: ${missing[*]}"
        echo "    Install them and try again."
        exit 1
    fi
}

input_fork() {
    local tries=0
    while true; do
        echo -e "\n${BLD}Fork URL${RST}"
        echo -e "  ${DIM}https://github.com/you/Dumpify${RST}"
        read -p "  > " -re url

        url=$(echo "$url" | sed 's|/$||;s|\.git$||')
        local user repo
        user=$(echo "$url" | sed -E 's|.*github\.com[:/]||' | cut -d'/' -f1)
        repo=$(echo "$url" | sed -E 's|.*github\.com[:/]||' | cut -d'/' -f2)

        if [[ -n "$user" && -n "$repo" ]]; then
            printf "  Checking... "
            local code
            code=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/$user/$repo" || echo "000")
            if [[ "$code" == "200" ]]; then
                ok "$user/$repo"
                G_USER="$user"
                G_REPO="$repo"
                return 0
            fi
            fail "Repository not found"
        else
            fail "Invalid format"
        fi

        tries=$((tries + 1))
        [[ $tries -ge 3 ]] && { fail "Too many attempts"; exit 1; }
    done
}

input_token() {
    local tries=0
    while true; do
        echo -e "\n${BLD}Token${RST}"
        echo -e "  ${DIM}github.com/settings/tokens${RST}"
        read -p "  > " -rs token
        echo ""
        token=$(echo "$token" | tr -d '\r\n' | xargs)

        [[ -z "$token" ]] && { fail "Empty"; tries=$((tries + 1)); [[ $tries -ge 3 ]] && exit 1; continue; }

        printf "  Verifying... "
        local hdr body
        hdr=$(mktemp)
        body=$(curl -s -D"$hdr" -H "Authorization: token $token" "https://api.github.com/user")
        local login scopes
        login=$(echo "$body" | jq -r '.login // empty')
        scopes=$(grep -i 'x-oauth-scopes' "$hdr" 2>/dev/null | head -1 | sed 's/.*: //' | tr -d '\r')
        rm -f "$hdr"

        if [[ -z "$login" ]]; then
            fail "Invalid token"
            tries=$((tries + 1))
            [[ $tries -ge 3 ]] && { fail "Too many attempts"; exit 1; }
            continue
        fi

        if [[ "$login" != "$G_USER" ]]; then
            fail "Token belongs to $login"
            tries=$((tries + 1))
            [[ $tries -ge 3 ]] && { fail "Too many attempts"; exit 1; }
            continue
        fi

        ok "$login"
        if [[ "$scopes" != *"repo"* ]]; then
            warn "Missing 'repo' scope — delete may fail"
        fi
        G_TOKEN="$token"
        return 0
    done
}

input_url() {
    echo -e "\n${BLD}ROM / OTA URL${RST}"
    read -p "  > " -re ota_url

    [[ -z "$ota_url" ]] && { fail "Empty URL"; exit 1; }

    printf "  Checking... "
    local code
    code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 10 "$ota_url" || echo "000")
    if [[ "$code" =~ ^(200|301|302|303|307|308)$ ]]; then
        ok "Reachable (HTTP $code)"
    else
        fail "Unreachable (HTTP $code)"
        exit 1
    fi
}

trigger() {
    echo -e "\n${BLD}Trigger${RST}"

    # Check existing branches
    printf "  Scanning branches... "
    local branches
    branches=$(curl -s -H "Authorization: token $G_TOKEN" \
        "https://api.github.com/repos/$G_USER/$G_REPO/branches?per_page=100" \
        | jq -r '.[].name' | grep -v '^master$' | grep -v '^main$')

    if [[ -n "$branches" ]]; then
        echo ""
        warn "Existing dumps found:"
        while IFS= read -r b; do echo "      $b"; done <<< "$branches"
        echo ""
        read -p "  Delete and re-dump? [y/N] " -re confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            printf "  Checking permissions... "
            local test_del
            test_del=$(curl -s -w "%{http_code}" -X DELETE -H "Authorization: token $G_TOKEN" \
                "https://api.github.com/repos/$G_USER/$G_REPO/refs/heads/__delete_test__")
            if [[ "$test_del" == "404" || "$test_del" == "422" || "$test_del" == "204" ]]; then
                ok ""
            else
                fail "No delete permission"
                echo "    Recreate token with 'repo' scope"
                exit 1
            fi

            while IFS= read -r b; do
                local enc
                enc=$(echo "$b" | sed 's|/|%2F|g')
                local resp code
                resp=$(curl -s -w "\n%{http_code}" -X DELETE -H "Authorization: token $G_TOKEN" \
                    "https://api.github.com/repos/$G_USER/$G_REPO/refs/heads/$enc")
                code=$(echo "$resp" | tail -1)
                case "$code" in
                    204) echo "      $b — deleted" ;;
                    422|404) echo "      $b — gone" ;;
                    *) fail "$b — HTTP $code" ;;
                esac
            done <<< "$branches"
        else
            info "Keeping existing dumps"
        fi
    else
        ok "No existing dumps"
    fi

    # Dispatch workflow
    printf "  Starting workflow... "
    local escaped_url resp code
    escaped_url=$(echo "$ota_url" | sed 's/"/\\"/g')
    resp=$(curl -s -w "\n%{http_code}" \
        -X POST -H "Authorization: token $G_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$G_USER/$G_REPO/actions/workflows/dump.yml/dispatches" \
        -d "{\"ref\":\"master\",\"inputs\":{\"urls\":\"$escaped_url\"}}")
    code=$(echo "$resp" | tail -1)

    if [[ "$code" != "204" ]]; then
        fail "HTTP $code"
        echo "$resp" | head -n -1
        exit 1
    fi
    ok ""

    # Wait for run
    printf "  Waiting for run... "
    sleep 5
    local runs run_id run_url
    runs=$(curl -s -H "Authorization: token $G_TOKEN" \
        "https://api.github.com/repos/$G_USER/$G_REPO/actions/runs?per_page=1&event=workflow_dispatch")
    run_id=$(echo "$runs" | jq -r '.workflow_runs[0].id // empty')
    run_url=$(echo "$runs" | jq -r '.workflow_runs[0].html_url // empty')

    if [[ -z "$run_id" ]]; then
        fail "Not found"
        exit 1
    fi
    ok ""
    echo -e "  ${DIM}$run_url${RST}"
    G_RUN_ID="$run_id"
    G_RUN_URL="$run_url"
}

show_logs() {
    local jobs job_id
    jobs=$(curl -s -H "Authorization: token $G_TOKEN" \
        "https://api.github.com/repos/$G_USER/$G_REPO/actions/runs/$G_RUN_ID/jobs")
    local step
    step=$(echo "$jobs" | jq -r '.jobs[0].steps[] | select(.conclusion == "failure") | .name' | head -1)
    [[ -n "$step" ]] && echo -e "  ${RED}Step:${RST} $step"
    job_id=$(echo "$jobs" | jq -r '.jobs[0].id')
    if [[ -n "$job_id" ]]; then
        curl -s -H "Authorization: token $G_TOKEN" \
            "https://api.github.com/repos/$G_USER/$G_REPO/actions/jobs/$job_id/logs" \
            | tail -20 | sed 's/^/    /'
    fi
}

poll() {
    echo ""
    local bar_w=20
    local t0=$(date +%s)
    local status_file=$(mktemp)
    local done=0

    # Background API poller
    ( while [[ "$done" != "1" ]]; do
        curl -s -H "Authorization: token $G_TOKEN" \
            "https://api.github.com/repos/$G_USER/$G_REPO/actions/runs/$G_RUN_ID/jobs" \
            > "$status_file" 2>/dev/null
        sleep 5
    done ) &
    local bg=$!
    trap "done=1; kill $bg 2>/dev/null; rm -f $status_file" RETURN

    local spin=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local si=0

    while true; do
        local jobs
        jobs=$(cat "$status_file" 2>/dev/null)
        [[ -z "$jobs" ]] && { sleep 1; continue; }

        local total comp=0 cur="Preparing..." conc="pending" idx=0 snum=0
        total=$(echo "$jobs" | jq '.jobs[0].steps | length' 2>/dev/null)
        [[ -z "$total" || "$total" -eq 0 ]] && total=1

        while IFS='|' read -r st cn nm; do
            if [[ "$st" == "completed" ]]; then
                comp=$((idx + 1)); snum=$((idx + 1)); cur="$nm"; conc="$cn"
            elif [[ "$st" == "in_progress" ]]; then
                snum=$((idx + 1)); cur="$nm"; conc="running"
            fi
            idx=$((idx + 1))
        done < <(echo "$jobs" | jq -r '.jobs[0].steps[] | "\(.status)|\(.conclusion // "pending")|\(.name)"' 2>/dev/null)

        local filled=$(( comp * bar_w / total ))
        local empty=$(( bar_w - filled ))
        local pct=$(( comp * 100 / total ))
        local bar=""
        local i
        for ((i=0; i<filled; i++)); do bar+="━"; done
        for ((i=0; i<empty; i++)); do bar+="─"; done

        local now=$(date +%s)
        local elapsed=$(( now - t0 ))
        local em=$(( elapsed / 60 ))
        local es=$(( elapsed % 60 ))

        local ch="✓"
        [[ "$conc" == "running" ]] && ch="${spin[$si]}"
        si=$(( (si + 1) % ${#spin[@]} ))

        printf "\033[2K\r  ${bar} %3d%%  [%d/%d] %s" "$pct" "$snum" "$total" "$cur"
        printf "\n  ${DIM}%s${RST}  %dm%02ds\033[A" "$ch" "$em" "$es"

        local jst jcn
        jst=$(echo "$jobs" | jq -r '.jobs[0].status' 2>/dev/null)
        jcn=$(echo "$jobs" | jq -r '.jobs[0].conclusion // "pending"' 2>/dev/null)

        if [[ "$jst" == "completed" ]]; then
            done=1
            kill $bg 2>/dev/null
            local tf=$(( $(date +%s) - t0 ))
            printf "\033[2K\r  ${bar} %3d%%  [%d/%d] %s" "100" "$total" "$total" "Done!"
            printf "\n  ✓  %dm%02ds\033[A\n\n" "$((tf/60))" "$((tf%60))"
            rm -f "$status_file"
            if [[ "$jcn" == "success" ]]; then
                return 0
            else
                fail "Workflow failed"
                echo "  $G_RUN_URL"
                show_logs
                return 1
            fi
        fi

        sleep 1
    done
}

main() {
    echo -e "${BLD}"
    echo "  ╔═══════════════════════════════╗"
    echo "  ║         D U M P I F Y         ║"
    echo "  ╚═══════════════════════════════╝"
    echo -e "${RST}"

    check_deps
    input_fork
    input_token
    input_url
    trigger
    poll || exit 1
    info "Dump saved: https://github.com/$G_USER/$G_REPO/branches"

    echo -e "\n  ${GRN}Done.${RST}\n"
}

main "$@"
