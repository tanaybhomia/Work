#!/usr/bin/env bash

# -----------------------------------------------------
# Work Tracker v13.0 (Clean Developer Edition)
# Features: Pomodoro, ETA, Switch, Auto-Backups, Archive
# -----------------------------------------------------

DATA_DIR="$HOME/.worktracker"
DATA_FILE="$DATA_DIR/worklog.csv"
STATE_FILE="$DATA_DIR/.state"
PAUSED_FILE="$DATA_DIR/.paused"
GLOBAL_GOAL_FILE="$DATA_DIR/.global_goal"
PROJ_GOAL_FILE="$DATA_DIR/.project_goals"
ARCHIVE_FILE="$DATA_DIR/.archived"

# Setup
mkdir -p "$DATA_DIR"
touch "$DATA_FILE" "$PROJ_GOAL_FILE" "$ARCHIVE_FILE"
if [ ! -s "$DATA_FILE" ]; then echo "date,project,minutes,tag,note,start_time,end_time" > "$DATA_FILE"; fi

# --- THEME ---
bold=$(tput bold); dim=$(tput dim); reset=$(tput sgr0)
c_accent=$(tput setaf 4); c_clock=$(tput setaf 5); c_subtle=$(tput setaf 8)
c_success=$(tput setaf 2); c_warn=$(tput setaf 3); c_err=$(tput setaf 1)
c_cyan=$(tput setaf 6)

# --- UTILS ---
notify_user() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e "display notification \"$1\" with title \"Work Tracker\""
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send -u normal -i "utilities-terminal" -t 5000 "Work Tracker" "$1"
    fi
}

play_sound() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    elif command -v paplay >/dev/null 2>&1; then
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
    elif command -v aplay >/dev/null 2>&1; then
        aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null &
    else
        echo -e "\a"
    fi
}

set_window_title() { echo -ne "\033]0;$1\007"; }
format_time() { printf "%02d:%02d:%02d" $(($1/3600)) $(( ($1%3600)/60 )) $(($1%60)); }

# --- DATA HELPERS ---
get_global_goal() { 
    local g=$(cat "$GLOBAL_GOAL_FILE" 2>/dev/null)
    [[ "$g" =~ ^[0-9]+$ ]] && echo "$g" || echo "8" 
}
get_project_goal() {
    local g=$(grep "^$1," "$PROJ_GOAL_FILE" 2>/dev/null | cut -d',' -f2)
    [[ "$g" =~ ^[0-9]+$ ]] && echo "$g" || echo ""
}
get_today_total() {
    awk -F',' -v d="$(date +%Y-%m-%d)" 'NR>1 && $1==d {sum+=$3} END{print sum+0}' "$DATA_FILE"
}
get_today_project_total() {
    awk -F',' -v d="$(date +%Y-%m-%d)" -v p="$1" 'NR>1 && $1==d && $2==p {sum+=$3} END{print sum+0}' "$DATA_FILE"
}

# --- PROJECT SELECTOR ---
select_project() {
    local projects=$(awk -F',' -v arch_file="$ARCHIVE_FILE" '
        BEGIN { while((getline < arch_file) > 0) arch[$0]=1 }
        NR>1 { if (!($2 in arch)) print $2 }
    ' "$DATA_FILE" | sort | uniq -c | sort -nr | awk '{$1=""; print $0}' | sed 's/^ //')
    
    if command -v fzf >/dev/null 2>&1; then
        local selected=$(echo "$projects" | fzf --height=10 --reverse --prompt="Select/Type > " --print-query)
        local query=$(echo "$selected" | head -n1)
        local match=$(echo "$selected" | tail -n1)
        if [ -n "$match" ] && [ "$match" != "$query" ]; then echo "$match"; else echo "$query"; fi
        return
    fi
    if [ -z "$projects" ]; then read -p "Enter new project name: " p >&2; echo "$p"; return; fi
    echo -e "${bold}${c_accent}Select Project:${reset}" >&2
    IFS=$'\n' read -r -d '' -a proj_array <<< "$projects"
    local i=1
    for p in "${proj_array[@]}"; do echo "  ${dim}[$i]${reset} $p" >&2; ((i++)); done
    echo "  ${dim}[N]${reset} New Project" >&2
    read -p "${bold}> ${reset}" choice >&2
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#proj_array[@]}" ] && [ "$choice" -gt 0 ]; then
        echo "${proj_array[$((choice-1))]}"
    else read -p "Project Name: " manual_name >&2; echo "$manual_name"; fi
}

# --- TIMER UI ---
draw_timer_screen() {
    local elapsed=$1; local project=$2; local mode=$3; local pct=$4; local label=$5
    local pomo_len="${6:-25}"
    
    local lines=$(tput lines); local cols=$(tput cols)
    local center_row=$(( lines / 2 - 4 )); [ $center_row -lt 0 ] && center_row=0

    # Explicit centering to prevent ANSI-related right-shifting
    print_c() { 
        local row=$1; local text="$2"; local raw_len=$3
        local pad=$(( (cols - raw_len) / 2 )); [ $pad -lt 0 ] && pad=0
        printf "\033[%d;1H\033[K%*s%b" "$row" "$pad" "" "$text"
    }

    print_c $center_row "${dim}FOCUSING ON${reset}" 11
    print_c $((center_row + 1)) "${bold}${c_accent}${project}${reset}" ${#project}
    
    local time_str=$(format_time $elapsed)
    print_c $((center_row + 3)) "${bold}${c_clock}${time_str}${reset}" 8

    local width=40; local filled=$(( (pct * width) / 100 )); local empty=$((width - filled))
    local bar_str=""; for ((i=0; i<filled; i++)); do bar_str+="━"; done
    local empty_str=""; for ((i=0; i<empty; i++)); do empty_str+="─"; done
    
    local lbl_str="${label} ${pct}%"
    print_c $((center_row + 5)) "${c_subtle}${lbl_str}${reset}" ${#lbl_str}
    print_c $((center_row + 6)) "${c_accent}${bar_str}${c_subtle}${empty_str}${reset}" $width
    
    local status_msg=""
    local status_len=0
    if [ "$mode" == "pomodoro" ]; then
         local w_sec=$((pomo_len * 60))
         local cycle_sec=$((w_sec + (pomo_len > 45 ? 600 : 300) ))
         if (( (elapsed % cycle_sec) < w_sec )); then 
            status_msg="${c_success}[WORK PHASE]${reset}"; status_len=12
         else 
            status_msg="${c_warn}[BREAK PHASE]${reset}"; status_len=13
         fi
    else 
        status_msg="${dim}(Ctrl+C for options)${reset}"; status_len=20
    fi
    print_c $((center_row + 8)) "$status_msg" $status_len
    printf "\033[%d;1H" $lines
}

# --- SESSION RUNNER ---
run_session() {
    local project="$1"; local tag="$2"; local mode="$3"; local session_goal="$4"; local offset="${5:-0}"
    local pomo_len="${6:-25}"
    
    local start_time=$(($(date +%s) - offset))
    local total_sleep_time=0
    local last_tick=$(date +%s)
    local last_pomo_state="" 
    local last_hour_notified=$(( offset / 3600 ))
    
    local elapsed=0; local pct=0; local label=""

    project=$(echo "$project" | tr -d '\n\r')
    [ -z "$session_goal" ] && session_goal=$(get_project_goal "$project")
    [[ ! "$session_goal" =~ ^[0-9]+$ ]] && session_goal=""

    echo "$project,$start_time,$tag,$mode,$$,$session_goal,$pomo_len" > "$STATE_FILE"
    notify_user "[STARTED] $project"
    
    tput civis; stty -echo -echoctl; tput clear
    
    trap 'cleanup_term; remote_exit' SIGTERM
    trap 'cleanup_term; exit 1' SIGQUIT SIGABRT
    trap 'confirm_exit' SIGINT SIGTSTP 

    cleanup_term() { tput cnorm; stty echo echoctl; }

    pause_session_internal() {
        local current_elapsed=$(( $(date +%s) - start_time - total_sleep_time ))
        echo "$project,$current_elapsed,$tag,$mode,$session_goal,$pomo_len" > "$PAUSED_FILE"
        rm -f "$STATE_FILE"; cleanup_term
        echo -e "\n${c_accent}[PAUSED]${reset} Session paused."; exit 0
    }

    save_and_exit() {
        local dur=$(( ($(date +%s) - start_time - total_sleep_time) / 60 ))
        cleanup_term
        echo -e "\n"
        
        if [ "$dur" -lt 5 ]; then
             echo -e "${c_err}[DISCARDED] Session under 5 minutes.${reset}"
             rm -f "$STATE_FILE"; rm -f "$PAUSED_FILE"; exit 0
        fi
        
        notify_user "[FINISHED] $project ($dur min)"
        echo -e "${bold}[STOPPING]${reset} $project ($dur min)"
        read -e -p "Note (optional): " note < /dev/tty
        note=$(echo "$note" | tr ',' ';') 
        
        cp "$DATA_FILE" "$DATA_DIR/worklog.bak"
        cp "$DATA_FILE" "$DATA_DIR/worklog_$(date +%s).bak"
        ls -t "$DATA_DIR"/worklog_*.bak 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
        
        local end_time=$(( start_time + (dur * 60) ))
        local start_date_stamp start_hhmm end_hhmm
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            start_date_stamp=$(date -r "$start_time" +%Y-%m-%d)
            start_hhmm=$(date -r "$start_time" +%H:%M)
            end_hhmm=$(date -r "$end_time" +%H:%M)
        else
            start_date_stamp=$(date -d "@$start_time" +%Y-%m-%d)
            start_hhmm=$(date -d "@$start_time" +%H:%M)
            end_hhmm=$(date -d "@$end_time" +%H:%M)
        fi
        
        echo "$start_date_stamp,$project,$dur,$tag,$note,$start_hhmm,$end_hhmm" >> "$DATA_FILE"
        rm -f "$STATE_FILE"; rm -f "$PAUSED_FILE"; exit 0
    }
    
    confirm_exit() {
        local lines=$(tput lines); local cols=$(tput cols)
        local center_row=$(( lines / 2 - 4 )); [ $center_row -lt 0 ] && center_row=0
        local menu_row=$((center_row + 8)) 

        # Clear menu area
        for ((i=0; i<6; i++)); do printf "\033[%d;1H\033[K" $((menu_row + i)); done
        
        local pad1=$(( (cols - 12) / 2 )); [ $pad1 -lt 0 ] && pad1=0
        local pad2=$(( (cols - 30) / 2 )); [ $pad2 -lt 0 ] && pad2=0
        
        printf "\033[%d;1H\033[K%*s%b" "$menu_row" "$pad1" "" "${bold}${c_warn}TIMER PAUSED${reset}"
        printf "\033[%d;1H\033[K%*s%b" $((menu_row + 2)) "$pad2" "" "${bold}[P]${reset}ause   ${bold}[S]${reset}top   ${bold}[C]${reset}ontinue"
        
        while true; do
            read -r -s -n 1 key < /dev/tty
            case "$key" in
                p|P) pause_session_internal ;;
                s|S) save_and_exit ;;
                c|C|$'\e'|"") 
                    tput clear
                    draw_timer_screen "$elapsed" "$project" "$mode" "$pct" "$label" "$pomo_len"
                    break 
                    ;;
            esac
        done
    }

    remote_exit() { rm -f "$STATE_FILE"; cleanup_term; exit 0; }
    
    local work_sec=$((pomo_len * 60))
    local break_sec=$((pomo_len > 45 ? 600 : 300))
    local cycle_sec=$((work_sec + break_sec))
    
    while true; do
        local now=$(date +%s); local tick_diff=$((now - last_tick))
        if [ "$tick_diff" -gt 2 ]; then total_sleep_time=$((total_sleep_time + tick_diff - 1)); fi
        last_tick=$now
        elapsed=$((now - start_time - total_sleep_time))
        
        local current_hour=$(( elapsed / 3600 ))
        if [ "$current_hour" -gt "$last_hour_notified" ] && [ "$current_hour" -gt 0 ]; then
            play_sound
            notify_user "[MILESTONE] ${current_hour} hour(s) focused on $project"
            last_hour_notified=$current_hour
        fi
        
        if [ "$mode" == "pomodoro" ]; then
            local p_mod=$((elapsed % cycle_sec))
            local current_pomo_state=""
            if (( p_mod < work_sec )); then current_pomo_state="work"; else current_pomo_state="break"; fi
            
            if [ -n "$last_pomo_state" ] && [ "$last_pomo_state" != "$current_pomo_state" ]; then
                 play_sound 
                 if [ "$current_pomo_state" == "break" ]; then notify_user "[BREAK] Focus phase complete"; else notify_user "[FOCUS] Back to work on $project"; fi
            fi
            last_pomo_state="$current_pomo_state"
        fi

        local past_mins=0; local target_h=8; label="Daily Goal"
        if [ -n "$session_goal" ]; then
            past_mins=$(get_today_project_total "$project")
            target_h="$session_goal"; label="Target: $project"
        else
            past_mins=$(get_today_total); target_h=$(get_global_goal)
        fi
        
        local target_m=$(( target_h * 60 )); (( target_m == 0 )) && target_m=480
        local total_curr_mins=$(( (elapsed / 60) + past_mins ))
        pct=$(( (total_curr_mins * 100) / target_m ))
        (( pct > 100 )) && pct=100

        set_window_title "⏱ $(format_time $elapsed) - $project"
        draw_timer_screen "$elapsed" "$project" "$mode" "$pct" "$label" "$pomo_len"
        read -t 1 -n 1 _ignore < /dev/tty || true
    done
}

# --- NEW: TIMEFLOW LOGIC (CLEAN) ---
show_timeflow() {
    local input_date=$(echo "${1:-today}" | tr '[:upper:]' '[:lower:]')
    local target_date=""
    local current_year=$(date +%Y)

    case "$input_date" in
        today|t|"") target_date=$(date +%Y-%m-%d) ;;
        yesterday|y)
            if [[ "$OSTYPE" == "darwin"* ]]; then target_date=$(date -v-1d +%Y-%m-%d)
            else target_date=$(date -d "yesterday" +%Y-%m-%d); fi ;;
        [0-9][0-9][0-9][0-9]) 
            local d=${input_date:0:2}; local m=${input_date:2:2}
            target_date="$current_year-$m-$d" ;;
        *) target_date="$input_date" ;;
    esac

    local display_label="$target_date"
    if [ "$target_date" == "$(date +%Y-%m-%d)" ]; then display_label="TODAY ($target_date)"
    elif [ "$target_date" == "$([[ "$OSTYPE" == "darwin"* ]] && date -v-1d +%Y-%m-%d || date -d "yesterday" +%Y-%m-%d)" ]; then display_label="YESTERDAY ($target_date)"; fi

    echo -e "\n  ${bold}${c_accent}TIMEFLOW : ${display_label}${reset}"
    echo "  ──────────────────────────────────────────────────"
    
    awk -F',' -v d="$target_date" -v c_dim="$dim" -v c_rst="$reset" -v c_bld="$bold" -v c_cya="$c_cyan" '
    NR>1 && $1 == d {
        st = $6 != "" ? $6 : "--:--"
        et = $7 != "" ? $7 : "--:--"
        note = $5 != "" ? " (" substr($5,1,30) ")" : ""
        printf "  %s%s - %s%s  |  %s%4sm%s  |  %s%-14s%s%s%s%s\n", c_dim, st, et, c_rst, c_bld, $3, c_rst, c_cya, substr($2,1,14), c_rst, c_dim, note, c_rst
        found=1
    }
    END { if (!found) print "  " c_dim "No activities recorded for this date." c_rst }
    ' "$DATA_FILE"
    echo ""
}

# --- NEW: LIVE DASHBOARD (CLEAN) ---
show_dashboard() {
    tput civis; tput smcup; tput clear
    trap 'tput rmcup; tput cnorm; exit 0' SIGINT SIGTERM
    
    while true; do
        tput cup 0 0
        local out="\n  ${bold}LIVE DASHBOARD${reset}\n"
        out+="  ──────────────────────────────────────────────────\n\n"
        
        local today_mins=$(get_today_total)
        local goal=$(get_global_goal)
        local goal_m=$(( goal * 60 ))
        
        if [ -f "$STATE_FILE" ]; then
            IFS=',' read -r project start_time tag mode pid session_goal pomo_len < "$STATE_FILE"
            local elapsed_sec=$(( $(date +%s) - start_time ))
            out+="  STATUS  : ${bold}${c_success}RUNNING${reset}\n"
            out+="  PROJECT : ${c_cyan}$project${reset}\n"
            out+="  SESSION : $(format_time $elapsed_sec)\n"
            today_mins=$(( today_mins + (elapsed_sec / 60) ))
        elif [ -f "$PAUSED_FILE" ]; then
            IFS=',' read -r project elapsed tag mode session_goal pomo_len < "$PAUSED_FILE"
            out+="  STATUS  : ${bold}${c_warn}PAUSED${reset}\n"
            out+="  PROJECT : ${c_cyan}$project${reset}\n"
            out+="  SESSION : $(format_time $elapsed)\n"
            today_mins=$(( today_mins + (elapsed / 60) ))
        else
            out+="  STATUS  : ${dim}IDLE${reset}\n"
            out+="  PROJECT : -\n"
            out+="  SESSION : 00:00:00\n"
        fi
        
        local pct=$(( (today_mins * 100) / goal_m ))
        [ $pct -gt 100 ] && pct=100
        local width=40
        local filled=$(( (pct * width) / 100 ))
        local empty=$(( width - filled ))
        local bar_str=""; for((i=0; i<filled; i++)); do bar_str+="█"; done
        local empty_str=""; for((i=0; i<empty; i++)); do empty_str+="░"; done
        
        out+="\n  PROGRESS: $((today_mins/60))h $((today_mins%60))m / ${goal}h (${pct}%)\n"
        out+="  ${c_accent}${bar_str}${c_subtle}${empty_str}${reset}\n"
        out+="\n  ──────────────────────────────────────────────────\n"
        
        echo -e "$out"
        show_timeflow "$(date +%Y-%m-%d)"
        tput ed 
        sleep 1
    done
}


# --- ANALYTICS REPORTS ---
list_projects() {
    echo -e "\n  ${bold}${c_accent}PROJECT DIRECTORY${reset}"
    echo "  ──────────────────────────────────────────────────"
    
    local raw_data
    raw_data=$(awk -F',' -v arch_file="$ARCHIVE_FILE" '
        BEGIN { while((getline < arch_file) > 0) arch[$0]=1 }
        NR>1 {
            p = $2; sub(/\r$/, "", p)
            if (p == "") next
            if (p in arch) { arch_entries[p]++; arch_sum[p]+=$3 }
            else { entries[p]++; sum[p]+=$3 }
        }
        END {
            for (p in sum) printf "%s|%d|%d|active\n", p, entries[p], sum[p]
            for (p in arch_sum) printf "%s|%d|%d|archived\n", p, arch_entries[p], arch_sum[p]
        }
    ' "$DATA_FILE" | sort -t'|' -k3 -nr)
    
    local active_list="" archived_list="" has_archived=0
    
    while IFS='|' read -r name count mins status; do
        [ -z "$name" ] && continue
        local hours=$(echo "scale=1; $mins / 60" | bc 2>/dev/null || awk "BEGIN {printf \"%.1f\", $mins/60}")
        local formatted_line
        
        if [ "$status" == "archived" ]; then
            printf -v formatted_line "  ${dim}%-20s %3d sessions  %6s h${reset}\n" "${name:0:20}" "$count" "$hours"
            archived_list+="$formatted_line"
            has_archived=1
        else
            printf -v formatted_line "  ${bold}%-20s${reset} ${dim}%3d sessions${reset}  ${c_success}%6s h${reset}\n" "${name:0:20}" "$count" "$hours"
            active_list+="$formatted_line"
        fi
    done <<< "$raw_data"
    
    echo -e "  ${bold}ACTIVE PROJECTS${reset}"
    if [ -n "$active_list" ]; then echo -ne "$active_list"; else echo "  ${dim}No active projects.${reset}\n"; fi
    
    if [ $has_archived -eq 1 ]; then
        echo "  ──────────────────────────────────────────────────"
        echo -e "  ${dim}ARCHIVED PROJECTS${reset}"
        echo -ne "$archived_list"
    fi
    echo "  ──────────────────────────────────────────────────"
    echo ""
}

show_chart() { echo -e "\n  ${bold}${c_accent}ACTIVITY CHART (Last 7 Days)${reset}\n  ──────────────────────────────────────────────────"; local dates=""; if [[ "$OSTYPE" == "darwin"* ]]; then for i in {6..0}; do dates="$dates $(date -v-${i}d +%Y-%m-%d)"; done; else for i in {6..0}; do dates="$dates $(date -d "$i days ago" +%Y-%m-%d)"; done; fi; local max_min=0; declare -A day_sum; for d in $dates; do local s=$(awk -F',' -v d="$d" '$1==d {sum+=$3} END{print sum+0}' "$DATA_FILE"); day_sum[$d]=$s; if (( s > max_min )); then max_min=$s; fi; done; [ "$max_min" -eq 0 ] && max_min=1; for d in $dates; do local val=${day_sum[$d]}; local day_name=$(date -d "$d" +%a 2>/dev/null || date -j -f "%Y-%m-%d" "$d" +%a); local bar_len=$(( (val * 30) / max_min )); local bar=""; for ((i=0; i<bar_len; i++)); do bar+="█"; done; if [ "$val" -gt 0 ] && [ "$bar_len" -eq 0 ]; then bar="▌"; fi; local color=$c_success; if [ "$val" -gt 300 ]; then color=$c_accent; fi; if [ "$val" -gt 480 ]; then color=$c_warn; fi; local hours=$(echo "scale=1; $val / 60" | bc 2>/dev/null || awk "BEGIN {printf \"%.1f\", $val/60}"); printf "  ${dim}%s %s${reset} | ${color}%-30s${reset} ${bold}%s h${reset}\n" "$d" "$day_name" "$bar" "$hours"; done; echo "  ──────────────────────────────────────────────────\n"; }
show_tags_report() { local filter="${1:-all}"; local start_date="1970-01-01"; local title="ALL-TIME TAGS"; case "$filter" in today) start_date=$(date +%Y-%m-%d); title="TODAY'S TAGS" ;; week) start_date=$([[ "$OSTYPE" == "darwin"* ]] && date -v-Sun +%Y-%m-%d || date -d "last sunday" +%Y-%m-%d); title="WEEKLY TAGS" ;; month) start_date=$(date +%Y-%m-01); title="MONTHLY TAGS" ;; esac; echo -e "\n  ${bold}${c_accent}$title${reset} ${dim}($filter)${reset}\n  ──────────────────────────────────────────────────"; awk -F',' -v s="$start_date" -v acc="$c_accent" -v res="$reset" 'NR>1 && $1 >= s { t = ($4 == "") ? "No Tag" : $4; sum[t] += $3; total += $3 } END { if (total==0) { print "  No data."; exit } for (t in sum) { pct = (sum[t]/total)*100; printf "  %-12s %3dh %02dm %s(%d%%)%s\n", substr(t,1,12), int(sum[t]/60), sum[t]%60, acc, pct, res } print ""; print "  TOTAL: " int(total/60) "h " total%60 "m" }' "$DATA_FILE" | sort -nr -k 2; echo ""; }
show_weekly_report() { if [[ "$OSTYPE" == "darwin"* ]]; then local target_dow=$(date +%u); local diff=$((target_dow - 1)); local start_week=$(date -v-${diff}d +%Y-%m-%d); else local start_week=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d); if [ "$(date +%u)" -eq 1 ]; then start_week=$(date +%Y-%m-%d); fi; fi; echo -e "\n  ${bold}${c_accent}WEEKLY LOG${reset} ${dim}(Since $start_week)${reset}\n  ────────────────────────────────────────────────────────────"; printf "  ${bold}%-12s %-15s %-10s %-10s %s${reset}\n" "Date" "Project" "Time" "Tag" "Note"; echo "  ────────────────────────────────────────────────────────────"; awk -F',' -v start="$start_week" -v acc="$c_accent" -v res="$reset" 'NR>1 && $1 >= start { h = int($3/60); m = $3%60; time = sprintf("%dh %02dm", h, m); printf "  %-12s %-15s %-10s %-10s %s\n", $1, substr($2,1,14), time, substr($4,1,9), substr($5,1,25); total_min += $3 } END { print "  ────────────────────────────────────────────────────────────"; printf "  TOTAL: " acc "%.1f Hours" res "\n", total_min/60 }' "$DATA_FILE"; echo ""; }
show_summary() { local filter="${1:-today}"; local global_goal=$(get_global_goal); (( global_goal == 0 )) && global_goal=8; local start_date=""; local title=""; local mode="range"; case "$filter" in today) start_date=$(date +%Y-%m-%d); title="TODAY'S INSIGHTS"; mode="exact" ;; yesterday) if [[ "$OSTYPE" == "darwin"* ]]; then start_date=$(date -v-1d +%Y-%m-%d); else start_date=$(date -d "yesterday" +%Y-%m-%d); fi; title="YESTERDAY'S SUMMARY"; mode="exact" ;; week) start_date=$([[ "$OSTYPE" == "darwin"* ]] && date -v-Sun +%Y-%m-%d || date -d "last sunday" +%Y-%m-%d); title="WEEKLY OVERVIEW"; mode="range" ;; month) start_date=$(date +%Y-%m-01); title="MONTHLY ANALYTICS"; mode="range" ;; ????-??-??) start_date="$filter"; title="SUMMARY FOR $filter"; mode="exact" ;; *) start_date="1970-01-01"; title="ALL-TIME STATISTICS"; mode="range" ;; esac; echo -e "\n  ${bold}${c_accent}$title${reset} ${dim}($filter)${reset}\n  ──────────────────────────────────────────────────"; awk -F',' -v s="$start_date" -v m="$mode" -v goal="$global_goal" -v arch_file="$ARCHIVE_FILE" -v acc="$c_accent" -v res="$reset" -v bld="$bold" -v suc="$c_success" -v clr_sub="$c_subtle" 'BEGIN { while((getline < arch_file) > 0) arch[$0]=1 } NR>1 { if (m == "exact" && $1 != s) next; if (m == "range" && $1 < s) next; p_name = $2; if (p_name in arch) p_name = "[Archived]"; sum[p_name] += $3; count++; total += $3; } END { if (total == 0) { print "  No data found for this period."; exit } if (m == "exact") { goal_m = goal * 60; pct = int((total * 100) / goal_m); if (pct > 100) pct = 100; width = 40; filled = int((pct * width) / 100); empty = width - filled; bar_str = ""; for(i=0; i<filled; i++) bar_str = bar_str "█"; empty_str = ""; for(i=0; i<empty; i++) empty_str = empty_str "░"; printf "  PROGRESS  %s%s%s%s %s%d%%%s\n\n", suc, bar_str, clr_sub, empty_str, bld, pct, res } print "  " bld "DISTRIBUTION" res; for (p in sum) { pct = (total > 0) ? (sum[p]/total)*100 : 0; bl = int(pct/5); bar=""; for(i=0;i<20;i++) bar = (i<bl) ? bar "█" : bar "░"; printf "  %-12s %3dh %02dm %s%s%s %3d%%\n", substr(p,1,12), int(sum[p]/60), sum[p]%60, acc, bar, res, pct } }' "$DATA_FILE" | sort -nr -k5; echo -e "  ──────────────────────────────────────────────────\n"; }

# --- NEW: BLINGED HELP MENU ---
show_help() {
    tput clear
    echo -e "${c_accent}"
    cat << "EOF"
  _       __           __   ______               __           
 | |     / /___  _____/ /_ /_  __/________ _____/ /_____  _____
 | | /| / / __ \/ ___/ //_/ / / / ___/ __ `/ ___/ //_/ _ \/ ___/
 | |/ |/ / /_/ / /  / ,<   / / / /  / /_/ / /__/ ,< /  __/ /    
 |__/|__/\____/_/  /_/|_| /_/ /_/   \__,_/\___/_/|_|\___/_/     
EOF
    echo -e "${reset}"
    echo -e "    ${dim}v13.0 - Developer Edition${reset}\n"
    
    echo -e "    ${bold}CORE COMMANDS${reset}"
    echo -e "      ${c_success}start${reset} [proj]    Start timer. ${dim}(Flags: --pomo 50, --tag coding)${reset}"
    echo -e "      ${c_success}stop${reset}            End session, add note, and trigger auto-backup."
    echo -e "      ${c_success}switch${reset} [proj]   Instantly jump to a new project."
    echo -e "      ${c_success}pause / resume${reset}  Pause or resume the current session.\n"

    echo -e "    ${bold}VIEWS & STATS${reset}"
    echo -e "      ${c_accent}dash${reset}            Open the live dashboard (running timer + daily progress)."
    echo -e "      ${c_accent}day${reset} [date]      View timeflow (e.g., 'yesterday' or '2303' for 23rd Mar)."
    echo -e "      ${c_accent}eta${reset}             Predicts exactly when you can clock out."
    echo -e "      ${c_accent}summary${reset} [rng]   Data breakdowns for: today, yesterday, week, month."
    echo -e "      ${c_accent}chart / tags${reset}    Visual 7-day graphs and tag analysis.\n"

    echo -e "    ${bold}MANAGEMENT${reset}"
    echo -e "      ${c_warn}archive${reset} [p...]  Hide old projects from your main menus."
    echo -e "      ${c_warn}projects${reset}        List all Active and Archived projects."
    echo -e "      ${c_warn}edit${reset}            Open the raw CSV log in Nano/Vim."
    echo -e "      ${c_warn}undo${reset}            Delete the very last entry you made.\n"
}

# --- CONTROLLER ---
case "$1" in
    start)
        shift; proj=""; mode="standard"; tag=""; goal=""; pomo_arg="25"
        while [[ "$#" -gt 0 ]]; do
            case $1 in 
                --pomo) mode="pomodoro"; if [[ "$2" =~ ^[0-9]+$ ]]; then pomo_arg="$2"; shift; fi;; 
                --tag) tag="$2"; shift;; 
                --goal) goal="$2"; shift;; 
                *) proj="$1";; 
            esac; shift
        done
        [ -z "$proj" ] && proj=$(select_project)
        [ -z "$proj" ] && exit 1
        run_session "$proj" "$tag" "$mode" "$goal" "" "$pomo_arg" ;;
    
    switch)
        shift; new_proj="$1"; shift
        if [ ! -f "$STATE_FILE" ]; then echo "[ERROR] No active session to switch from."; exit 1; fi
        IFS=',' read -r old_proj start_time tag mode pid session_goal pomo_len < "$STATE_FILE"
        duration=$(( ($(date +%s) - start_time) / 60 ))
        if [ "$duration" -ge 5 ]; then
            local end_time=$(( start_time + (duration * 60) ))
            local start_hhmm end_hhmm start_date_stamp
            if [[ "$OSTYPE" == "darwin"* ]]; then
                start_date_stamp=$(date -r "$start_time" +%Y-%m-%d)
                start_hhmm=$(date -r "$start_time" +%H:%M)
                end_hhmm=$(date -r "$end_time" +%H:%M)
            else
                start_date_stamp=$(date -d "@$start_time" +%Y-%m-%d)
                start_hhmm=$(date -d "@$start_time" +%H:%M)
                end_hhmm=$(date -d "@$end_time" +%H:%M)
            fi
            echo "$start_date_stamp,$old_proj,$duration,$tag,Switched to $new_proj,$start_hhmm,$end_hhmm" >> "$DATA_FILE"
            echo "[SAVED] $old_proj ($duration m)"
            cp "$DATA_FILE" "$DATA_DIR/worklog.bak"
        else
            echo "[DISCARDED] Previous session too short (< 5m)."
        fi
        rm -f "$STATE_FILE"; [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
        exec "$0" start "$new_proj" "$@" ;;

    dash|dashboard) show_dashboard ;;
    day|timeflow) show_timeflow "$2" ;;

    eta)
        global_goal=$(get_global_goal); today_mins=$(get_today_total)
        if [ -f "$STATE_FILE" ]; then
            IFS=',' read -r _ start _ _ _ _ _ < "$STATE_FILE"
            today_mins=$((today_mins + (($(date +%s) - start) / 60)))
        fi
        goal_mins=$((global_goal * 60)); remaining=$((goal_mins - today_mins))
        echo -e "\n  ${bold}ESTIMATED FINISH TIME${reset}\n  ──────────────────────────"
        echo "  Goal:      ${global_goal}h ($goal_mins m)"
        echo "  Completed: $((today_mins/60))h $((today_mins%60))m"
        if [ "$remaining" -le 0 ]; then echo -e "  ${c_success}[GOAL MET] You are technically free.${reset}\n"
        else
            finish_time=$([[ "$OSTYPE" == "darwin"* ]] && date -v+${remaining}M +%I:%M%p || date -d "+$remaining minutes" +%I:%M%p)
            echo "  Remaining: ${remaining} m"
            echo -e "  Clock Out: ${bold}${c_accent}$finish_time${reset}\n"
        fi ;;

    archive)
        shift
        if [ -z "$1" ]; then echo "Usage: work archive [Project]..."; exit 1; fi
        for p in "$@"; do
            if grep -qx "$p" "$ARCHIVE_FILE" 2>/dev/null; then echo "[WARN] '$p' is already archived."
            else echo "$p" >> "$ARCHIVE_FILE"; echo "[ARCHIVED] $p"; fi
        done ;;
        
    unarchive)
        shift
        if [ -z "$1" ]; then echo "Usage: work unarchive [Project]..."; exit 1; fi
        for p in "$@"; do
            if [[ "$OSTYPE" == "darwin"* ]]; then sed -i '' "/^$p$/d" "$ARCHIVE_FILE"; else sed -i "/^$p$/d" "$ARCHIVE_FILE"; fi
            echo "[RESTORED] $p"
        done ;;

    edit)
        ${EDITOR:-nano} "$DATA_FILE"
        echo "[OK] Edit complete." ;;

    pause)
        if [ ! -f "$STATE_FILE" ]; then echo "[ERROR] No active session."; exit 1; fi
        IFS=',' read -r project start_time tag mode pid session_goal pomo_len < "$STATE_FILE"
        current_elapsed=$(( $(date +%s) - start_time ))
        echo "$project,$current_elapsed,$tag,$mode,$session_goal,$pomo_len" > "$PAUSED_FILE"
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null; rm -f "$STATE_FILE"
        echo "[PAUSED] '${bold}$project${reset}' at $(format_time $current_elapsed)." ;;
        
    resume)
        if [ -f "$STATE_FILE" ]; then echo "[ERROR] Session already running: $(cut -d',' -f1 "$STATE_FILE")"; exit 1; fi
        if [ -f "$PAUSED_FILE" ]; then
            IFS=',' read -r project elapsed tag mode session_goal pomo_len < "$PAUSED_FILE"
            echo "[RESUMING] '${bold}$project${reset}' from pause..."; rm -f "$PAUSED_FILE"
            run_session "$project" "$tag" "$mode" "$session_goal" "$elapsed" "$pomo_len"; exit 0
        fi
        last_entry=$(tail -n 1 "$DATA_FILE")
        if [ -z "$last_entry" ] || [ "$last_entry" == "date,project,minutes,tag,note,start_time,end_time" ]; then echo "[ERROR] No history to resume."; exit 1; fi
        last_proj=$(echo "$last_entry" | awk -F',' '{print $2}'); last_tag=$(echo "$last_entry" | awk -F',' '{print $4}')
        echo "[STARTING] New session for: ${bold}$last_proj${reset}"
        run_session "$last_proj" "$last_tag" "standard" "" "" "25" ;;
        
    stop)
        if [ -f "$STATE_FILE" ]; then
            IFS=',' read -r project start_time tag mode pid session_goal pomo_len < "$STATE_FILE"
            duration=$(( ($(date +%s) - start_time) / 60 ))
            if [ "$duration" -lt 5 ]; then
                 echo -e "${c_err}[DISCARDED] Session under 5 minutes.${reset}"
                 rm -f "$STATE_FILE"; [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null; exit 0
            fi
            notify_user "[FINISHED] $project ($duration min)"
            echo -e "${bold}[STOPPING]${reset} $project ($duration min)"
            read -e -p "Note (optional): " note
            note=$(echo "$note" | tr ',' ';') 
            
            cp "$DATA_FILE" "$DATA_DIR/worklog.bak"
            cp "$DATA_FILE" "$DATA_DIR/worklog_$(date +%s).bak"
            ls -t "$DATA_DIR"/worklog_*.bak 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
            
            local end_time=$(( start_time + (duration * 60) ))
            local start_hhmm end_hhmm start_date_stamp
            
            if [[ "$OSTYPE" == "darwin"* ]]; then
                start_date_stamp=$(date -r "$start_time" +%Y-%m-%d)
                start_hhmm=$(date -r "$start_time" +%H:%M)
                end_hhmm=$(date -r "$end_time" +%H:%M)
            else
                start_date_stamp=$(date -d "@$start_time" +%Y-%m-%d)
                start_hhmm=$(date -d "@$start_time" +%H:%M)
                end_hhmm=$(date -d "@$end_time" +%H:%M)
            fi
            
            echo "$start_date_stamp,$project,$duration,$tag,$note,$start_hhmm,$end_hhmm" >> "$DATA_FILE"
            rm -f "$STATE_FILE"; [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
            echo "[SAVED] Entry recorded." ; exit 0
        fi
        if [ -f "$PAUSED_FILE" ]; then
            IFS=',' read -r project elapsed tag mode session_goal pomo_len < "$PAUSED_FILE"
            duration=$(( elapsed / 60 ))
            if [ "$duration" -lt 5 ]; then
                 echo -e "${c_err}[DISCARDED] Session under 5 minutes.${reset}"
                 rm -f "$PAUSED_FILE"; exit 0
            fi
            notify_user "[FINISHED] $project ($duration min)"
            echo -e "${bold}[STOPPING PAUSED]${reset} $project ($duration min)"
            read -e -p "Note (optional): " note
            note=$(echo "$note" | tr ',' ';')
            echo "$(date +%Y-%m-%d),$project,$duration,$tag,$note,--:--,--:--" >> "$DATA_FILE"
            rm -f "$PAUSED_FILE"; echo "[SAVED] Entry recorded."; exit 0
        fi
        echo "[ERROR] No active or paused session."; exit 1 ;;
        
    goal)
        shift; if [ "$1" == "set" ]; then 
            if [ -z "$2" ] || [ -z "$3" ]; then echo "Usage: work goal set [Project] [Hours]"; exit 1; fi
            if [[ "$OSTYPE" == "darwin"* ]]; then sed -i '' "/^$2,/d" "$PROJ_GOAL_FILE"; else sed -i "/^$2,/d" "$PROJ_GOAL_FILE"; fi
            echo "$2,$3" >> "$PROJ_GOAL_FILE"; echo "[OK] Goal set: $2 = $3 hours/day"
        elif [ "$1" == "global" ]; then echo "$2" > "$GLOBAL_GOAL_FILE"; echo "[OK] Global Goal set to $2 hours"
        else show_help; fi ;;
        
    chart) show_chart ;;
    tags) show_tags_report "$2" ;;
    projects|list) list_projects ;;
    
    undo) 
        read -p "Delete last entry? (y/N) " c
        [[ "$c" =~ ^[Yy]$ ]] && ( [[ "$OSTYPE" == "darwin"* ]] && sed -i '' '$d' "$DATA_FILE" || sed -i '$d' "$DATA_FILE" ) && echo "[OK] Deleted." ;;
    week) show_weekly_report ;;
    summary) show_summary "$2" ;;
    
    status) 
        if [ -f "$STATE_FILE" ]; then echo "[TRACKING] $(cut -d',' -f1 "$STATE_FILE")"
        elif [ -f "$PAUSED_FILE" ]; then echo "[PAUSED] $(cut -d',' -f1 "$PAUSED_FILE")"
        else echo "[IDLE]"; fi ;;
    help|--help|-h|"") show_help ;;
    *) show_help ;;
esac
