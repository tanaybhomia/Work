#!/usr/bin/env bash

# -----------------------------------------------------
# Work Tracker v7 (Complete Edition)
# Features: Interactive Menu, Pomodoro, Invoice, Summary, Streak
# -----------------------------------------------------

DATA_DIR="$HOME/.worktracker"
DATA_FILE="$DATA_DIR/worklog.csv"
STATE_FILE="$DATA_DIR/.state"
PID_FILE="$DATA_DIR/.worker_pid"
STREAK_FILE="$DATA_DIR/.streak"
CONFIG_FILE="$DATA_DIR/config"
IDLE_LIMIT=300 # 5 Minutes
DEFAULT_RATE=50 # Default hourly rate

# Ensure Setup
mkdir -p "$DATA_DIR"
touch "$DATA_FILE" "$STREAK_FILE" "$CONFIG_FILE"
if [ ! -s "$DATA_FILE" ]; then echo "date,project,minutes,tag,note" > "$DATA_FILE"; fi

# Load Config
if grep -q "RATE=" "$CONFIG_FILE"; then
  HOURLY_RATE=$(grep "RATE=" "$CONFIG_FILE" | cut -d'=' -f2)
else
  HOURLY_RATE=$DEFAULT_RATE
fi

# Colors
green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4); red=$(tput setaf 1); bold=$(tput bold); reset=$(tput sgr0)

# --- UTILS ---

notify_user() {
  local title="Work Tracker"
  local msg="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    osascript -e "display notification \"$msg\" with title \"$title\""
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "$title" "$msg"
  fi
}

get_idle_time() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo $(($(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF; exit}') / 1000000000))
  elif command -v xprintidle >/dev/null 2>&1; then
    echo $(($(xprintidle) / 1000))
  else
    echo 0
  fi
}

# --- STREAK MANAGEMENT ---
update_streak() {
  local today yesterday current_streak last_date
  today=$(date +%Y-%m-%d)
  yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
  read -r last_date current_streak < "$STREAK_FILE" 2>/dev/null || current_streak=0

  if [ "$last_date" = "$today" ]; then
    echo "$today $current_streak" > "$STREAK_FILE"
  elif [ "$last_date" = "$yesterday" ]; then
    current_streak=$((current_streak + 1))
    echo "$today $current_streak" > "$STREAK_FILE"
  else
    echo "$today 1" > "$STREAK_FILE"
  fi
}

show_streak() {
  if [ -s "$STREAK_FILE" ]; then
    read -r _ streak < "$STREAK_FILE"
    echo "🔥 ${yellow}Current streak:${reset} $streak day(s)"
  fi
}

# --- INTERACTIVE SELECTOR ---
select_project() {
  local projects
  projects=$(awk -F',' 'NR>1 {print $2}' "$DATA_FILE" | sort | uniq -c | sort -nr | awk '{$1=""; print $0}' | sed 's/^ //')

  if [ -z "$projects" ]; then
    read -p "Enter new project name: " p; echo "$p"; return
  fi

  if command -v fzf >/dev/null 2>&1; then
    local selected=$(echo "$projects" | fzf --height=10 --prompt="Select Project > " --print-query)
    local query=$(echo "$selected" | head -n1)
    local match=$(echo "$selected" | tail -n1)
    if [ "$match" != "$query" ] && [ -n "$match" ]; then echo "$match"; else echo "$query"; fi
  else
    echo "${blue}Select project:${reset}"
    IFS=$'\n' read -r -d '' -a proj_array <<< "$projects"
    select p in "${proj_array[@]}" "New Project"; do
      if [ "$p" == "New Project" ]; then read -p "Name: " n; echo "$n"; else echo "$p"; fi; break
    done
  fi
}

# --- START TIMER ---
start_timer() {
  local project="$1"; local mode="standard"; local tag=""
  shift
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --pomo|--pomodoro) mode="pomodoro" ;;
      --tag) tag="$2"; shift ;;
      *) if [ -z "$project" ]; then project="$1"; fi ;;
    esac
    shift
  done

  [ -z "$project" ] && project=$(select_project)
  [ -z "$project" ] && exit 1
  [ -f "$STATE_FILE" ] && echo "⚠️  Timer running." && exit 1

  echo "$project,$(date +%s),$tag,$mode" > "$STATE_FILE"

  if [ "$mode" == "pomodoro" ]; then
    echo "🍅 ${red}Pomodoro Mode${reset} '$project' (25m work/5m break)"
  else
    echo "⏱️  ${green}Tracking${reset} '$project'"
  fi
  notify_user "Started '$project'"

  # Background Worker
  (
    while [ -f "$STATE_FILE" ]; do
      sleep 60
      if [ -f "$STATE_FILE" ]; then
        IFS=',' read -r p s t m < "$STATE_FILE"
        now=$(date +%s); elapsed=$(( (now - s) / 60 ))

        if [ "$m" != "pomodoro" ]; then
           if (( elapsed > 0 && elapsed % 60 == 0 )); then notify_user "⏳ '$p': $((elapsed/60)) hrs"; fi
        else
          cycle=$(( elapsed % 30 ))
          [ "$cycle" -eq 25 ] && notify_user "🍅 Take a break (5 min)!"
          [ "$cycle" -eq 0 ] && [ "$elapsed" -gt 0 ] && notify_user "🚀 Back to work!"
        fi
      fi
    done
  ) &
  echo $! > "$PID_FILE"
}

# --- STOP TIMER ---
stop_timer() {
  [ ! -f "$STATE_FILE" ] && echo "❌ No timer." && exit 1
  if [ -f "$PID_FILE" ]; then kill "$(cat "$PID_FILE")" 2>/dev/null; rm -f "$PID_FILE"; fi

  IFS=',' read -r project start_time tag mode < "$STATE_FILE"
  local duration=$(( ($(date +%s) - start_time) / 60 ))

  local idle_s=$(get_idle_time)
  if [ "$idle_s" -gt "$IDLE_LIMIT" ]; then
    local idle_min=$(( idle_s / 60 ))
    echo "💤 Deducting $idle_min min idle time."
    duration=$(( duration - idle_min ))
    (( duration < 0 )) && duration=0
  fi

  echo -n "📝 Note: "
  read -r note

  echo "$(date +%Y-%m-%d),$project,$duration,$tag,$note" >> "$DATA_FILE"
  rm -f "$STATE_FILE"
  update_streak
  echo "✅ ${green}Stopped${reset} '$project' (${duration} min)."
  show_streak
}

# --- REPORTING FUNCTIONS ---
show_week_graph() {
  echo ""
  echo "📈 ${yellow}Weekly Activity${reset}"
  local start_date=$(date -d "last sunday" +%Y-%m-%d 2>/dev/null || date -v-Sun +%Y-%m-%d)
  for i in {0..6}; do
    d=$(date -d "$start_date +$i day" +%Y-%m-%d 2>/dev/null || date -v+${i}d -j -f %Y-%m-%d "$start_date" +%Y-%m-%d)
    day_name=$(date -d "$d" +%a 2>/dev/null || date -j -f %Y-%m-%d "$d" +%a)
    total=$(awk -F',' -v d="$d" 'NR>1 && $1==d {sum+=$3} END{print sum+0}' "$DATA_FILE")

    # Scale: 1 block = 15 mins
    blocks=$(( total / 15 ))
    bar=""; for ((x=0; x<blocks; x++)); do bar+="█"; done
    [ -z "$bar" ] && bar="."
    printf "%s | %-30s %3d min\n" "$day_name" "$bar" "$total"
  done
}

show_summary() {
  local filter="$1"
  echo "📊 ${yellow}Work Summary${reset} ($filter)"
  echo "---------------------------------"

  # Calculate date range
  local today=$(date +%Y-%m-%d)
  local start_date=""
  case "$filter" in
    today) start_date=$today ;;
    week)  start_date=$(date -d "last sunday" +%Y-%m-%d 2>/dev/null || date -v-Sun +%Y-%m-%d) ;;
    month) start_date=$(date +%Y-%m-01) ;;
    *) start_date="1970-01-01" ;; # All time
  esac

  # Table view
  awk -F',' -v s="$start_date" '
  NR>1 && $1 >= s { sum[$2] += $3 }
  END { for (p in sum) printf "%-15s %4d min (%.1f h)\n", p, sum[p], sum[p]/60 }
  ' "$DATA_FILE" | sort -k2 -nr

  show_week_graph
  echo ""
  show_streak
}

generate_invoice() {
  local month=$(date +%Y-%m); [ -n "$1" ] && month="$1"
  local outfile="Invoice_${month}.md"

  {
    echo "# 🧾 INVOICE - $month"
    echo "| Project | Hours | Rate | Total |"
    echo "|---|---|---|---|"
    awk -F',' -v r="$HOURLY_RATE" -v m="$month" '$1 ~ m {sum[$2]+=$3} END {
      for (p in sum) { h=sum[p]/60; printf "| %s | %.2f | $%s | $%.2f |\n", p, h, r, h*r; t+=h*r }
      printf "| **TOTAL** | | | **$%.2f** |\n", t
    }' "$DATA_FILE"
  } > "$outfile"
  echo "📄 Invoice saved: $outfile"
}

# --- CONTROLLER ---
case "$1" in
  start|work) shift; start_timer "$@" ;;
  stop)  stop_timer ;;
  status)
    [ -f "$STATE_FILE" ] && IFS=',' read -r p s t m < "$STATE_FILE" && el=$(( ($(date +%s) - s) / 60 )) && echo "⏳ $p: ${el}m ($m)" || echo "⚪ Idle."
    ;;
  summary) show_summary "${2:-today}" ;;
  invoice) generate_invoice "$2" ;;
  "") start_timer ;;
  *) echo "Usage: work {start|stop|status|summary [today/week/month]|invoice}" ;;
esac
