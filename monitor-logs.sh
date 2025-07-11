#!/bin/bash

# ==================================================
#        SCRIPT: monitor-logs.sh
#        Descrizione: Monitora log di sistema
#        Autore: Anshell (2025)
# ==================================================

# ========== VARIABILI GLOBALI ==========
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
logdir="$HOME/scheduled_logs"
logfile="$logdir/monitor-logs-$timestamp.log"
email="your_email@gmail.com"
hostname=$(hostname)
current_user=$(whoami)
auth_log="/var/log/auth.log"
fail2ban_log="/var/log/fail2ban.log"
ufw_log="/var/log/ufw.log"
monitor_file="$HOME/monitor/secret-script.sh"
audit_key="monitor_secret"
max_file_len=50

# ========== PREPARAZIONE ==========
sync && sleep 1
mkdir -p "$logdir"
exec > "$logfile" 2>&1

# ========== AUDITD RULE ==========
AUDIT_RULE_EXISTS=$(sudo auditctl -l | grep -F "$monitor_file")

# ========== HEADER ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│                                                              │"
echo "│ LOG MONITORING REPORT                                        │"
echo "│                                                              │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
printf "  Timestamp: %s\n" "$(date +"%Y-%m-%d %H:%M:%S")"
printf "  Hostname: %s\n" "$hostname"
echo "└──────────────────────────────────────────────────────────────┘"

# Funzione per formattare date
format_date() {
    raw="$1"
    if [[ "$raw" == *"T"* ]]; then
        date -d "$(echo "$raw" | cut -d'+' -f1 | sed 's/T/ /')" +"%Y-%m-%d %H:%M:%S"
    elif [[ "$raw" == *","* ]]; then
        date -d "$(echo "$raw" | cut -d',' -f1)" +"%Y-%m-%d %H:%M:%S"
    else
        echo "$raw"
    fi
}

# ========== SSH LOGIN FALLITI ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [!] SSH LOGIN FALLITI (ultimi 10)                            │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "Date                 | IP              | User      "
echo "--------------------------------------------------------------"

failed_lines=$(grep -aE "Failed password|Connection closed by authenticating user|Certificate invalid" "$auth_log" | grep -v "message repeated")
declare -A seen
while IFS= read -r line; do
    raw_date=$(echo "$line" | cut -d'T' -f1)
    raw_time=$(echo "$line" | cut -d'T' -f2 | cut -d'.' -f1)
    formatted_date="$raw_date $raw_time"

    if echo "$line" | grep -qE "authenticating user|Failed password"; then
        user=$(echo "$line" | grep -oP 'user \K\S+' || echo "<unknown>")
        ip=$(echo "$line" | grep -oP '\b(\d{1,3}\.){3}\d{1,3}\b' || echo "<unknown>")

        if [[ "$user" != "<unknown>" && "$ip" != "<unknown>" ]]; then
            key="${formatted_date}_${user}_${ip}"
            if [[ -z "${seen[$key]}" ]]; then
                printf "%-20s | %-15s | %-10s\n" "$formatted_date" "$ip" "$user"
                seen["$key"]=1
            fi
        fi
    fi
done <<< "$failed_lines" | tail -n 10

# ========== SSH LOGIN RIUSCITI ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [+] SSH LOGIN RIUSCITI (ultimi 10)                           │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "Date                 | IP              | User      "
echo "--------------------------------------------------------------"

grep -aE "Accepted (password|publickey)" "$auth_log" | tail -n 10 | while read -r line; do
    RAW_DATE=$(echo "$line" | cut -d' ' -f1)
    FORMATTED_DATE=$(format_date "$RAW_DATE")
    USER=$(echo "$line" | grep -oP 'for \K\S+')
    IP=$(echo "$line" | grep -oP 'from \K[\d\.]+')
    printf "%-20s | %-15s | %-10s\n" "$FORMATTED_DATE" "${IP:-<unknown>}" "${USER:-<unknown>}"
done

# ========== COMANDI SUDO ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [!] USO COMANDI SUDO (ultimi 10)                             │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "User            | Command"
echo "--------------------------------------------------------------"

SUDO_LOG=$(grep -a "COMMAND=" "$auth_log" | grep -vE 'auditctl|ausearch|monitor-logs\.sh' | tail -n 100)
echo "$SUDO_LOG" | tail -n 10 | while read -r line; do
    user=$(echo "$line" | sed -nE 's/^.*sudo: ([^:]+) :.*$/\1/p')
    cmd=$(echo "$line" | sed -E 's/^.*COMMAND=//')
    printf "%-15s | %s\n" "$user" "$cmd"
done

# ========== FAIL2BAN ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [!] FAIL2BAN – Attività (ultimi 10)                          │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "Operation         | IP              | Date                 "
echo "--------------------------------------------------------------"

grep -aE "Ban|Unban" "$fail2ban_log" | tail -n 10 | while read -r line; do
    ACTION=$(echo "$line" | grep -oE 'Ban|Unban')
    IP=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
    RAW_DATE=$(echo "$line" | cut -d' ' -f1,2)
    FORMATTED_DATE=$(format_date "$RAW_DATE")
    printf "%-17s | %-15s | %-20s\n" "$ACTION" "$IP" "$FORMATTED_DATE"
done

# ========== UFW ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [!] UFW – Connessioni Bloccate (ultimi 10)                   │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "Source IP        | Destination IP   | Port     "
echo "--------------------------------------------------------------"

grep "\[UFW BLOCK\]" "$ufw_log" | tail -n 50 | awk '
{
    for(i=1;i<=NF;i++){
        if($i ~ /SRC=/) src=substr($i,5);
        if($i ~ /DST=/) dst=substr($i,5);
        if($i ~ /DPT=/) port=substr($i,5);
    }
    if (src && dst && port) {
        printf "%-16s | %-16s | %-8s\n", src, dst, port;
        src=""; dst=""; port=""
    }
}' | awk 'prev != $0 { print; prev = $0 }' | tail -n 10

# ========== ACCESSI A FILE AUDITD ==========
echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ [*] ACCESSI A secret-script.sh (auditd)                      │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

if [ -z "$AUDIT_RULE_EXISTS" ]; then
    echo "[*] Setting auditd rule for $monitor_file"
    sudo auditctl -w "$monitor_file" -p rwxa -k "$audit_key"
fi

printf "%-19s | %-15s | %-*s\n" "Date" "User" "$max_file_len" "File"
printf -- "--------------------------------------------------------------------------------------\n"

declare -A seen_records

sudo ausearch -k "$audit_key" --start recent | grep -E 'msg=audit\([0-9]+\.[0-9]+:[0-9]+\):' | while read -r line; do
    ts=$(echo "$line" | grep -oP 'audit\(\K[0-9]+')
    date_str=$(date -d @"$ts" +"%Y-%m-%d %H:%M:%S")

    user=$(echo "$line" | grep -oP 'acct="\K[^"]+' || true)
    if [ -z "$user" ]; then
        uid_num=$(echo "$line" | grep -oP 'uid=\K[0-9]+' || true)
        [ -n "$uid_num" ] && user=$(getent passwd "$uid_num" | cut -d: -f1)
    fi
    if [ -z "$user" ]; then
        auid_num=$(echo "$line" | grep -oP 'auid=\K[0-9]+' || true)
        [ -n "$auid_num" ] && user=$(getent passwd "$auid_num" | cut -d: -f1)
    fi
    user=$(echo "$user" | xargs)

    [ -z "$user" ] || [ "$user" == "<unknown>" ] && continue

    key="${date_str}_${user}"
    if [[ -z "${seen_records[$key]}" ]]; then
        file_display="$monitor_file"
        [ ${#file_display} -gt $max_file_len ] && file_display="${file_display:0:$(($max_file_len-3))}..."
        printf "%-19s | %-15s | %-*s\n" "$date_str" "$user" "$max_file_len" "$file_display"
        seen_records[$key]=1
    fi

# ========== PULIZIA E CONCLUSIONE ==========
done
echo ""
find "$logdir" -type f -name "*.log" -mtime +7 -exec rm -f {} \;
echo "Il report di monitoraggio è pronto nel file: $logfile" | mail -s "Alert Log Monitor - $timestamp" "$email"
echo "Backup locale: report $logfile" | mail -s "Backup Log - $timestamp" "$current_user"
exec > /dev/tty

echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ Report completato!                                         │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""
echo "Output salvato in: $logfile"
echo "Email inviata a: $email"
echo "Backup locale in: /var/mail/$current_user"
echo ""
