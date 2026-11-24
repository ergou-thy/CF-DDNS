#!/bin/bash
#========================================================
#  ❀ 桃花源 · Cloudflare DDNS 一键部署（自包含版）
#  作者：桃花源      版本：v2.0
#  用法：bash ddns.sh
#
#  特点：
#   1. 单文件，菜单内嵌，不需要额外上传 ddns-menu.sh
#   2. 检测重复安装：覆盖 / 修复 / 卸载重装
#   3. 支持中文域名 / punycode 自动互转
#   4. 默认检测间隔 300 秒，DNS TTL 默认 60 秒
#   5. 安装后自动创建 ddns 快捷命令
#   6. 独立的换 IP 记录日志
#   7. 代理 / TTL / 间隔改动会自动同步到 Cloudflare
#========================================================

set -o pipefail

ESC=$'\033'
RED="${ESC}[31m"; GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"; CYAN="${ESC}[36m"; MAGENTA="${ESC}[35m"; NC="${ESC}[0m"
BOLD="${ESC}[1m"; DIM="${ESC}[2m"
PINK="${ESC}[38;5;218m"; PEACH="${ESC}[38;5;216m"
C_COLS=$(tput colors 2>/dev/null)
case "$C_COLS" in ''|*[!0-9]*) C_COLS=8 ;; esac
[ "$C_COLS" -lt 256 ] && { PINK="$MAGENTA"; PEACH="$YELLOW"; }

VERSION="2.0"
AUTHOR="桃花源"

API="https://api.cloudflare.com/client/v4"
INSTALL_DIR="/opt/cf-ddns"
CONF_FILE="$INSTALL_DIR/cf-ddns.conf"
RUN_FILE="$INSTALL_DIR/cf-ddns-run.sh"
MENU_FILE="$INSTALL_DIR/ddns-menu.sh"
LOG_FILE="/var/log/cf-ddns.log"
CHANGE_LOG="$INSTALL_DIR/ip-change.log"

hr(){ echo "   ${DIM}${BLUE}──────────────────────────────────────────────────────${NC}"; }
kv(){ printf "   ${DIM}%s${NC}  %s\n" "$1" "$2"; }
mi(){ printf "   ${GREEN}%s${NC}  %s\n" "$1" "$2"; }
banner(){ echo ""; echo "   ${DIM}${PINK}══════════════════════════════════════════════════════${NC}"; echo "    ${BOLD}${PINK}❀  $1${NC}"; echo "    ${DIM}$2${NC}"; echo "   ${DIM}${PINK}══════════════════════════════════════════════════════${NC}"; echo ""; }
msg(){ echo "   ${BLUE}»${NC} $*"; }
ok(){  echo "   ${GREEN}✓${NC} $*"; }
warn(){ echo "   ${YELLOW}!${NC} $*"; }
err(){ echo "   ${RED}✗${NC} $*"; }

# crontab 只能精确到分钟，间隔为 60 的整数倍时用 */n，否则退回每分钟
cron_expr(){
    local i="$1"
    if [ $((i % 60)) -eq 0 ] && [ $((i / 60)) -ge 1 ] && [ $((i / 60)) -le 59 ]; then
        echo "*/$((i / 60)) * * * *"
    else
        echo "* * * * *"
    fi
}

# 有 systemd 就只用 timer，避免 cron 与 timer 双跑刷日志
ensure_schedule(){
    local intv="$1" expr
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl daemon-reload 2>/dev/null
        if systemctl enable --now cf-ddns.timer 2>/dev/null; then
            ok "systemd timer 已启用（每 ${intv} 秒）"
            if crontab -l 2>/dev/null | grep -q "cf-ddns-run.sh"; then
                crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" > /tmp/cron.$$ || true
                crontab /tmp/cron.$$ 2>/dev/null
                rm -f /tmp/cron.$$
                ok "已清理重复的 crontab（交给 systemd 接管）"
            fi
            return 0
        fi
    fi
    if ! command -v crontab >/dev/null 2>&1; then
        warn "既无 systemd 也无 crontab，定时任务未配置"
        return 1
    fi
    expr=$(cron_expr "$intv")
    crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" > /tmp/cron.$$ || true
    echo "$expr bash $RUN_FILE >/dev/null 2>&1" >> /tmp/cron.$$
    crontab /tmp/cron.$$ && ok "crontab 已配置：$expr"
    rm -f /tmp/cron.$$
}

#========================================================
# 生成菜单文件（内嵌，heredoc 用 MENU_EOF 包裹）
#========================================================
write_menu(){
mkdir -p "$INSTALL_DIR"
cat > "$MENU_FILE" <<'MENU_EOF'
#!/bin/bash
#========================================================
#  ❀ 桃花源 · Cloudflare DDNS 管理台
#  作者：桃花源      版本：v2.0
#========================================================
ESC=$'\033'
RED="${ESC}[31m"; GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"; CYAN="${ESC}[36m"; MAGENTA="${ESC}[35m"; NC="${ESC}[0m"
BOLD="${ESC}[1m"; DIM="${ESC}[2m"
PINK="${ESC}[38;5;218m"; PEACH="${ESC}[38;5;216m"
C_COLS=$(tput colors 2>/dev/null)
case "$C_COLS" in ''|*[!0-9]*) C_COLS=8 ;; esac
[ "$C_COLS" -lt 256 ] && { PINK="$MAGENTA"; PEACH="$YELLOW"; }

VERSION="2.0"
AUTHOR="桃花源"
API="https://api.cloudflare.com/client/v4"

INSTALL_DIR="/opt/cf-ddns"
CONF_FILE="$INSTALL_DIR/cf-ddns.conf"
RUN_FILE="$INSTALL_DIR/cf-ddns-run.sh"
MENU_FILE="$INSTALL_DIR/ddns-menu.sh"
LOG_FILE="/var/log/cf-ddns.log"
CHANGE_LOG="$INSTALL_DIR/ip-change.log"

hr(){ echo "   ${DIM}${BLUE}──────────────────────────────────────────────────────${NC}"; }
title(){ echo ""; echo "   ${BOLD}${PINK}❀ $*${NC}"; hr; }
kv(){ printf "   ${DIM}%s${NC}  %s\n" "$1" "$2"; }
mi(){ printf "   ${GREEN}%s${NC}  %s\n" "$1" "$2"; }
ok(){ echo "   ${GREEN}✓${NC} $*"; }
warn(){ echo "   ${YELLOW}!${NC} $*"; }
err(){ echo "   ${RED}✗${NC} $*"; }
msgx(){ echo "   ${BLUE}»${NC} $*"; }
pause(){ echo ""; printf "   ${DIM}${PINK}❀${NC} ${DIM}按回车返回菜单…${NC}"; read -r _; }

# crontab 只能精确到分钟
cron_expr(){
    local i="$1"
    if [ $((i % 60)) -eq 0 ] && [ $((i / 60)) -ge 1 ] && [ $((i / 60)) -le 59 ]; then
        echo "*/$((i / 60)) * * * *"
    else
        echo "* * * * *"
    fi
}

# 由 systemd 接管时清掉 cron，避免同一分钟跑两遍
sync_cron(){
    local intv="$1" expr
    if systemctl is-active --quiet cf-ddns.timer 2>/dev/null; then
        if crontab -l 2>/dev/null | grep -q "cf-ddns-run.sh"; then
            crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" > /tmp/cf-cron.$$ || true
            crontab /tmp/cf-cron.$$ 2>/dev/null
            rm -f /tmp/cf-cron.$$
            ok "已清理重复 crontab（systemd 接管）"
        fi
        return 0
    fi
    command -v crontab >/dev/null 2>&1 || return 0
    expr=$(cron_expr "$intv")
    crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" > /tmp/cf-cron.$$ || true
    echo "$expr bash $RUN_FILE >/dev/null 2>&1" >> /tmp/cf-cron.$$
    crontab /tmp/cf-cron.$$ 2>/dev/null && ok "crontab 已同步：$expr"
    rm -f /tmp/cf-cron.$$
}

# 改完配置立刻跑一次，让 CF 记录跟上
apply_now(){
    [ -f "$RUN_FILE" ] || return 0
    msgx "正在同步到 Cloudflare…"
    bash "$RUN_FILE" 2>/dev/null
    sleep 1
    [ -f "$LOG_FILE" ] && tail -1 "$LOG_FILE" | sed 's/^/   /'
}

svc_state(){
    if systemctl is-active --quiet cf-ddns.timer 2>/dev/null; then
        echo "${GREEN}运行中${NC}"
    elif crontab -l 2>/dev/null | grep -q "cf-ddns-run.sh"; then
        echo "${YELLOW}仅 crontab${NC}"
    else
        echo "${RED}未启用${NC}"
    fi
}

next_run(){
    systemctl list-timers cf-ddns.timer --all 2>/dev/null \
        | awk 'NR>1 && /cf-ddns/ {print $1, $2, $3; exit}'
}

load_conf(){
    [ -f "$CONF_FILE" ] || return 1
    source "$CONF_FILE"
    return 0
}

get_public_ip(){
    local t m ip
    t=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --max-time 2 2>/dev/null)
    m=$(curl -s -H "X-aws-ec2-metadata-token: $t" --max-time 3 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    [ -z "$m" ] && m=$(curl -s --max-time 3 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    [[ "$m" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$m"; return 0; }
    for u in "https://api.ipify.org" "https://ifconfig.me/ip" \
             "https://ipv4.icanhazip.com" "https://ip.sb"; do
        ip=$(curl -4 -s --max-time 6 "$u" 2>/dev/null \
             | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -n "$ip" ] && { echo "$ip"; return 0; }
    done
    return 1
}

#========================================================
# 1. 运行状态
#========================================================
show_status(){
    title "运行状态"
    if [ ! -f "$CONF_FILE" ]; then
        err "尚未部署，请先执行 bash ddns.sh"
        pause; return
    fi
    load_conf

    echo ""
    echo "   ${BOLD}${PEACH}基本配置${NC}"; hr
    kv "域名" "${BOLD}${CYAN}${RECORD_DISPLAY:-$RECORD_NAME}${NC}"
    if [ -n "$RECORD_DISPLAY" ] && [ "$RECORD_DISPLAY" != "$RECORD_NAME" ]; then
        kv "编码" "${RECORD_NAME}   （punycode）"
    fi
    kv "区域" "${GREEN}${ZONE_NAME}${NC}"
    kv "标识" "$ZONE_ID"
    kv "代理" "$([ "$PROXIED" = "true" ] && echo "小黄云（隐藏源站）" || echo "灰云（仅 DNS）")"
    kv "间隔" "${INTERVAL:-300} 秒"
    kv "记录" "${RECORD_TYPE:-A}"
    kv "缓存" "TTL ${TTL:-60} 秒$( [ "$PROXIED" = "true" ] && echo "   ← 代理下由 CF 固定为 300 秒" )"

    echo ""
    echo "   ${BOLD}${PEACH}服务状态${NC}"; hr
    kv "状态" "$(svc_state)"
    NX=$(next_run)
    [ -n "$NX" ] && kv "下次" "$NX"
    if systemctl is-active --quiet cf-ddns.timer 2>/dev/null; then
        kv "定时" "systemd timer"
    elif [ -f /etc/systemd/system/cf-ddns.timer ]; then
        kv "定时" "systemd timer（未启动）"
    elif crontab -l 2>/dev/null | grep -q "cf-ddns-run.sh"; then
        kv "定时" "crontab"
    else
        kv "定时" "${YELLOW}未安装${NC}"
    fi

    echo ""
    echo "   ${BOLD}${PEACH}解析状态${NC}"; hr
    CF_IP=""; CF_PROX=""
    if [ -n "$API_TOKEN" ] && [ -n "$ZONE_ID" ] && [ -n "$RECORD_NAME" ]; then
        RESP=$(curl -s --max-time 12 \
            "$API/zones/$ZONE_ID/dns_records?type=${RECORD_TYPE:-A}&name=$RECORD_NAME" \
            -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
        if echo "$RESP" | grep -q '"success":true'; then
            CF_IP=$(echo "$RESP" | grep -oE '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
            CF_PROX=$(echo "$RESP" | grep -oE '"proxied":(true|false)' | head -1 | sed 's/.*://')
        fi
    fi
    if [ -n "$CF_IP" ]; then
        kv "云端" "${BOLD}${GREEN}${CF_IP}${NC}"
        kv "云朵" "$([ "$CF_PROX" = "true" ] && echo "小黄云（已代理）" || echo "灰云（仅 DNS）")"
    else
        kv "云端" "${YELLOW}记录不存在或查询失败${NC}"
    fi
    LOCAL_IP=$(get_public_ip)
    if [ -n "$LOCAL_IP" ]; then
        kv "本机" "${BOLD}${CYAN}${LOCAL_IP}${NC}"
        if [ -n "$CF_IP" ]; then
            if [ "$LOCAL_IP" = "$CF_IP" ]; then
                echo "   ${GREEN}✓ 解析与本机一致${NC}"
            else
                echo "   ${RED}✗ 解析与本机不一致，等待下次执行${NC}"
            fi
        fi
    else
        kv "本机" "${YELLOW}获取失败${NC}"
    fi

    echo ""
    echo "   ${BOLD}${PEACH}最近日志${NC}"; hr
    if [ -f "$LOG_FILE" ]; then
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/   /'
    else
        echo "   ${YELLOW}暂无运行日志${NC}"
    fi

    echo ""
    echo "   ${BOLD}${PEACH}最近换 IP${NC}"; hr
    if [ -f "$CHANGE_LOG" ]; then
        tail -5 "$CHANGE_LOG" 2>/dev/null | sed 's/^/   /'
    else
        echo "   ${YELLOW}暂无换 IP 记录${NC}"
    fi
    echo ""
    pause
}

#========================================================
# 2. 日志
#========================================================
view_log(){
    title "日志记录"
    mi 1 "运行日志 · 最近 30 行"
    mi 2 "运行日志 · 最近 100 行"
    mi 3 "运行日志 · 仅错误"
    mi 4 "运行日志 · 实时跟踪"
    mi 5 "换 IP 记录 · 全部"
    mi 6 "换 IP 记录 · 最近 20 条"
    mi 7 "换 IP 记录 · 按月统计"
    mi 8 "清空换 IP 记录"
    mi 0 "返回"
    echo ""
    read -rp "   请选择: " c
    case "$c" in
        1)
            if [ -f "$LOG_FILE" ]; then hr; tail -30 "$LOG_FILE"
            else warn "暂无运行日志"; fi
            ;;
        2)
            if [ -f "$LOG_FILE" ]; then hr; tail -100 "$LOG_FILE"
            else warn "暂无运行日志"; fi
            ;;
        3)
            if [ -f "$LOG_FILE" ]; then
                hr
                if grep -qE "失败|错误" "$LOG_FILE"; then
                    grep -E "失败|错误" "$LOG_FILE" | tail -30
                else
                    ok "没有错误记录"
                fi
            else warn "暂无运行日志"; fi
            ;;
        4)
            if [ -f "$LOG_FILE" ]; then
                echo "   ${YELLOW}实时跟踪中，Ctrl+C 退出${NC}"
                hr
                tail -f "$LOG_FILE"
            else warn "暂无运行日志"; fi
            ;;
        5)
            if [ -f "$CHANGE_LOG" ]; then
                hr
                echo "   ${DIM}共 $(wc -l < "$CHANGE_LOG" 2>/dev/null || echo 0) 条换 IP 记录${NC}"
                echo ""
                cat "$CHANGE_LOG"
            else
                warn "暂无换 IP 记录"
            fi
            ;;
        6)
            if [ -f "$CHANGE_LOG" ]; then hr; tail -20 "$CHANGE_LOG"
            else warn "暂无换 IP 记录"; fi
            ;;
        7)
            if [ -f "$CHANGE_LOG" ]; then
                hr
                awk '{print substr($1,1,7)}' "$CHANGE_LOG" 2>/dev/null \
                    | sort | uniq -c | awk '{printf "   %s   %s 次\n", $2, $1}'
            else warn "暂无换 IP 记录"; fi
            ;;
        8)
            if [ -f "$CHANGE_LOG" ]; then
                read -rp "   确认清空换 IP 记录？(y/N): " c2
                if [ "$c2" = "y" ]; then > "$CHANGE_LOG"; ok "已清空"; else warn "已取消"; fi
            else
                warn "暂无换 IP 记录"
            fi
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
    pause
}

#========================================================
# 3. 立即执行
#========================================================
run_now(){
    title "立即执行"
    if [ ! -f "$RUN_FILE" ]; then
        err "运行脚本不存在，请重新执行 bash ddns.sh 修复"
        pause; return
    fi
    msgx "正在执行…"
    B=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    bash "$RUN_FILE"
    sleep 1
    A=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    hr
    if [ "$A" -gt "$B" ]; then
        echo "   ${BOLD}本次输出${NC}"
        echo ""
        tail -c +$((B + 1)) "$LOG_FILE" | sed 's/^/   /'
    else
        warn "无新日志（可能被锁占用，或刚执行过）"
    fi
    pause
}

#========================================================
# 4. 修改配置
#========================================================
edit_conf(){
    title "修改配置"
    if [ ! -f "$CONF_FILE" ]; then
        err "配置文件不存在"
        pause; return
    fi
    load_conf

    echo ""
    echo "   ${BOLD}${PEACH}当前值${NC}"; hr
    kv "域名" "${RECORD_DISPLAY:-$RECORD_NAME}"
    kv "区域" "$ZONE_NAME"
    kv "代理" "$([ "$PROXIED" = "true" ] && echo "小黄云（已代理）" || echo "灰云（仅 DNS）")"
    kv "间隔" "${INTERVAL:-300} 秒"
    kv "缓存" "TTL ${TTL:-60} 秒$( [ "$PROXIED" = "true" ] && echo "（代理下由 CF 固定 300 秒）" )"
    echo ""
    mi 1 "修改节点域名（自动匹配 Zone）"
    mi 2 "修改检测间隔"
    mi 3 "切换代理模式（小黄云 / 灰云）"
    mi 4 "修改 API Token"
    mi 5 "修改 DNS 缓存 TTL"
    mi 6 "用编辑器打开配置文件"
    mi 0 "返回"
    echo ""
    read -rp "   请选择: " c

    case "$c" in
        1) change_domain; return ;;
        2)
            read -rp "   新间隔秒数 [当前 ${INTERVAL:-300}]: " v
            if [ -z "$v" ]; then warn "未修改"; pause; return; fi
            if ! echo "$v" | grep -qE '^[0-9]+$' || [ "$v" -lt 60 ]; then
                err "需 >= 60 秒"; pause; return
            fi
            sed -i "s/^INTERVAL=.*/INTERVAL=\"$v\"/" "$CONF_FILE"
            ok "间隔已改为 $v 秒"
            if [ -f /etc/systemd/system/cf-ddns.timer ]; then
                sed -i "s/^OnUnitActiveSec=.*/OnUnitActiveSec=${v}s/" /etc/systemd/system/cf-ddns.timer
                systemctl daemon-reload 2>/dev/null
                systemctl restart cf-ddns.timer 2>/dev/null
                ok "systemd timer 已同步"
            fi
            sync_cron "$v"
            ;;
        3)
            read -rp "   新值 true=小黄云 / false=灰云 [当前 $PROXIED]: " v
            if [ -z "$v" ]; then warn "未修改"; pause; return; fi
            v=$(printf '%s' "$v" | tr 'A-Z' 'a-z')
            if [ "$v" = "1" ]; then v="true"; fi
            if [ "$v" = "0" ]; then v="false"; fi
            if [ "$v" != "true" ] && [ "$v" != "false" ]; then
                err "只能填 true / false（或 1 / 0）"; pause; return
            fi
            sed -i "s/^PROXIED=.*/PROXIED=\"$v\"/" "$CONF_FILE"
            ok "代理已改为 $([ "$v" = "true" ] && echo "小黄云" || echo "灰云")"
            if [ "$v" = "true" ]; then
                warn "小黄云下 TTL 由 Cloudflare 固定为 300 秒，改 TTL 不会生效"
            fi
            apply_now
            ;;
        4)
            read -rp "   新 Token: " v
            if [ -z "$v" ]; then warn "未修改"; pause; return; fi
            sed -i "s|^API_TOKEN=.*|API_TOKEN=\"$v\"|" "$CONF_FILE"
            ok "Token 已更新"
            apply_now
            ;;
        5)
            echo "   ${DIM}TTL 取值：1 = 自动（300 秒），或 60 ~ 86400 秒${NC}"
            echo "   ${DIM}小黄云（已代理）时 CF 忽略此值，始终 300 秒${NC}"
            read -rp "   新 TTL 秒数 [当前 ${TTL:-60}]: " v
            if [ -z "$v" ]; then warn "未修改"; pause; return; fi
            if ! echo "$v" | grep -qE '^[0-9]+$'; then
                err "请输入数字"; pause; return
            fi
            if [ "$v" != "1" ] && { [ "$v" -lt 60 ] || [ "$v" -gt 86400 ]; }; then
                err "只能填 1 或 60 ~ 86400"; pause; return
            fi
            if grep -q '^TTL=' "$CONF_FILE"; then
                sed -i "s/^TTL=.*/TTL=$v/" "$CONF_FILE"
            else
                echo "TTL=$v" >> "$CONF_FILE"
            fi
            ok "TTL 已改为 $v 秒"
            apply_now
            ;;
        6)
            ${EDITOR:-vi} "$CONF_FILE"
            ok "已保存"
            ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
    pause
}

#========================================================
# 4b. 修改域名
#========================================================
change_domain(){
    title "修改节点域名"
    echo ""
    kv "当前" "${CYAN}${RECORD_DISPLAY:-$RECORD_NAME}${NC}"
    kv "区域" "${GREEN}${ZONE_NAME}${NC}"
    echo ""
    warn "旧域名的 DNS 记录不会删除，需要时请自行到 CF 控制台清理"
    echo ""
    read -rp "   新域名（留空取消）: " ND
    ND=$(echo "$ND" | tr -d '[:space:]' | sed 's#^https\?://##; s#/.*$##')
    if [ -z "$ND" ]; then warn "已取消"; pause; return; fi
    ND=$(printf '%s' "$ND" | tr 'A-Z' 'a-z')

    PY=""
    command -v python3 >/dev/null 2>&1 && PY=python3
    if [ -z "$PY" ]; then command -v python >/dev/null 2>&1 && PY=python; fi
    if [ -z "$PY" ]; then err "需要 python3"; pause; return; fi

    echo ""
    msgx "验证 Token 与域名..."

    ZJ=$(curl -s --max-time 20 "https://api.cloudflare.com/client/v4/zones?per_page=50" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
    echo "$ZJ" | grep -q '"success":true' || { err "Token 无效或网络不通"; pause; return; }

    RES=$(echo "$ZJ" | ND="$ND" $PY -c "
import sys, json, os
try:
    import idna
except ImportError:
    idna = None
def A(d):
    if not d: return d
    if d.isascii(): return d.lower()
    try:
        if idna: return idna.encode(d).decode('ascii').lower()
        return d.encode('idna').decode('ascii').lower()
    except Exception:
        return d.lower()
d = json.load(sys.stdin)
target = A(os.environ.get('ND','').strip())
best = None
allz = []
for z in (d.get('result') or []):
    n = z.get('name') or ''
    if not n: continue
    na = A(n); allz.append(n)
    if target == na or target.endswith('.' + na):
        if best is None or len(na) > len(best[1]):
            best = (z['id'], na, n)
if best:
    print(best[0] + '|' + best[2] + '|' + best[1])
else:
    print('NOTFOUND||' + ','.join(allz))
")

    ZID=$(echo "$RES" | cut -d'|' -f1)
    ZNM=$(echo "$RES" | cut -d'|' -f2)
    ZASC=$(echo "$RES" | cut -d'|' -f3)

    if [ "$ZID" = "NOTFOUND" ] || [ -z "$ZID" ]; then
        err "域名 $ND 不属于 Token 可访问的 Zone"
        echo ""
        echo "Token 可见域名:"
        echo "$ZASC" | tr ',' '\n' | while read -r z; do
            [ -n "$z" ] && echo "      ${CYAN}- $z${NC}"
        done
        pause; return
    fi

    ok "匹配成功: $ND → Zone $ZNM"

    DASC=$(ND="$ND" $PY -c "
import os
d = os.environ.get('ND','')
if d.isascii():
    print(d.lower())
else:
    try:
        import idna; print(idna.encode(d).decode('ascii'))
    except Exception:
        try: print(d.encode('idna').decode('ascii'))
        except Exception: print(d)
")

    sed -i "s|^ZONE_ID=.*|ZONE_ID=\"$ZID\"|" "$CONF_FILE"
    sed -i "s|^ZONE_NAME=.*|ZONE_NAME=\"$ZNM\"|" "$CONF_FILE"
    sed -i "s|^RECORD_NAME=.*|RECORD_NAME=\"$DASC\"|" "$CONF_FILE"
    sed -i "s|^RECORD_DISPLAY=.*|RECORD_DISPLAY=\"$ND\"|" "$CONF_FILE"

    ok "配置已更新"
    echo ""
    kv "域名" "${BOLD}${CYAN}$ND${NC}"
    kv "区域" "${GREEN}$ZNM${NC}"
    echo ""
    apply_now
    pause
}

#========================================================
# 5. 定时任务
#========================================================
toggle_service(){
    title "定时任务"
    echo ""
    mi 1 "启动 / 启用"
    mi 2 "停止 / 停用"
    mi 3 "重启"
    mi 0 "返回"
    echo ""
    read -rp "   请选择: " c
    echo ""
    case "$c" in
        1) systemctl enable --now cf-ddns.timer 2>/dev/null && ok "定时任务已启动" || err "启动失败，可能未安装 systemd timer" ;;
        2) systemctl disable --now cf-ddns.timer 2>/dev/null && ok "定时任务已停止" || err "停止失败" ;;
        3) systemctl restart cf-ddns.timer 2>/dev/null && ok "定时任务已重启" || err "重启失败" ;;
        0) return ;;
        *) warn "无效选择" ;;
    esac
    hr
    kv "状态" "$(svc_state)"
    NX=$(next_run)
    [ -n "$NX" ] && kv "下次" "$NX"
    pause
}

#========================================================
# 6. 连通测试
#========================================================
test_token(){
    title "连通测试"
    load_conf || { err "请先部署"; pause; return; }

    echo ""
    echo "   ${BOLD}${PEACH}配置摘要${NC}"; hr
    kv "令牌" "已配置（${#API_TOKEN} 位，已脱敏）"
    kv "区域" "${ZONE_NAME} / ${ZONE_ID}"
    kv "记录" "${RECORD_DISPLAY:-$RECORD_NAME}"
    kv "代理" "$([ "$PROXIED" = "true" ] && echo "小黄云（已代理）" || echo "灰云（仅 DNS）")"
    kv "缓存" "TTL ${TTL:-60} 秒$( [ "$PROXIED" = "true" ] && echo "（代理下 CF 固定 300 秒）" )"
    echo ""

    msgx "① Token 有效性"
    R=$(curl -s --max-time 12 "$API/user/tokens/verify" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
    if echo "$R" | grep -q '"status":"active"'; then ok "Token 有效"; else err "Token 无效或已过期"; fi

    echo ""
    msgx "② 区域可读性"
    R=$(curl -s --max-time 12 "$API/zones/$ZONE_ID" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
    if echo "$R" | grep -q '"success":true'; then
        ZN=$(echo "$R" | grep -oE '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
        ok "区域可读：$ZN"
    else
        err "区域读取失败"
    fi

    echo ""
    msgx "③ DNS 记录"
    R=$(curl -s --max-time 12 \
        "$API/zones/$ZONE_ID/dns_records?type=${RECORD_TYPE:-A}&name=$RECORD_NAME" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
    if echo "$R" | grep -q '"success":true'; then
        IP=$(echo "$R" | grep -oE '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
        RPX=$(echo "$R" | grep -oE '"proxied":(true|false)' | head -1 | sed 's/.*://')
        if [ -n "$IP" ]; then
            ok "记录存在：$IP   代理=$RPX"
        else
            warn "记录不存在，下次执行会自动创建"
        fi
    else
        err "查询失败"
    fi

    echo ""
    msgx "④ 本机公网 IP"
    LIP=$(get_public_ip)
    if [ -n "$LIP" ]; then ok "公网 IP：$LIP"; else err "获取失败"; fi
    pause
}

#========================================================
# 7. 批量部署
#========================================================
batch_deploy(){
    title "批量部署"
    load_conf || { err "请先完成本机部署以获取 Token"; pause; return; }
    echo ""
    echo "   ${DIM}目标机器需开放 SSH，稍后再执行 bash ddns.sh 补装运行环境${NC}"
    echo ""
    read -rp "   目标 IP，逗号分隔: " IPS
    read -rp "   对应域名，逗号分隔（顺序一致）: " DOMAINS
    read -rp "   1=小黄云 2=灰云 [1]: " PX
    [ -z "$PX" ] && PX=1
    [ "$PX" = "1" ] && PXV="true" || PXV="false"

    IFS=',' read -ra IPARR <<< "$IPS"
    IFS=',' read -ra DOMARR <<< "$DOMAINS"

    if [ "${#IPARR[@]}" -ne "${#DOMARR[@]}" ]; then
        err "IP 数(${#IPARR[@]}) 与 域名数(${#DOMARR[@]}) 不一致"; pause; return
    fi

    echo ""
    ok "将部署 ${#IPARR[@]} 台，Token 会写入目标机器"
    read -rp "   确认？(y/N): " c
    if [ "$c" != "y" ]; then warn "已取消"; pause; return; fi

    FAIL=0
    for i in "${!IPARR[@]}"; do
        IP=$(echo "${IPARR[$i]}" | tr -d ' ')
        DOM=$(echo "${DOMARR[$i]}" | tr -d ' ')
        echo ""; hr; echo "   ${CYAN}→ $IP  （$DOM）${NC}"
        if ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no "root@$IP" \
            "mkdir -p $INSTALL_DIR && cat > $CONF_FILE <<EOF
API_TOKEN=\"$API_TOKEN\"
ZONE_ID=\"$ZONE_ID\"
ZONE_NAME=\"$ZONE_NAME\"
RECORD_NAME=\"$DOM\"
RECORD_DISPLAY=\"$DOM\"
RECORD_TYPE=\"A\"
PROXIED=\"$PXV\"
TTL=${TTL:-60}
INTERVAL=\"${INTERVAL:-300}\"
EOF
chmod 600 $CONF_FILE" 2>/dev/null; then
            ok "$IP 配置已写入"
        else
            err "$IP 失败"; FAIL=$((FAIL+1))
        fi
    done
    echo ""
    if [ "$FAIL" -eq 0 ]; then
        ok "全部完成，目标机器再执行 bash ddns.sh 选 2 补装运行环境"
    else
        warn "$FAIL 台失败，请检查 SSH 与服务端网络"
    fi
    pause
}

#========================================================
# 8. 卸载
#========================================================
uninstall(){
    title "卸载"
    echo ""
    warn "将删除定时任务、配置文件、脚本、日志、快捷命令"
    warn "不会删除 Cloudflare 上的 DNS 记录"
    echo ""
    read -rp "   输入 yes 确认: " c
    if [ "$c" != "yes" ]; then warn "已取消"; pause; return; fi

    systemctl disable --now cf-ddns.timer 2>/dev/null
    rm -f /etc/systemd/system/cf-ddns.service /etc/systemd/system/cf-ddns.timer
    systemctl daemon-reload 2>/dev/null
    crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" | crontab - 2>/dev/null
    rm -f /usr/local/bin/ddns /etc/profile.d/cf-ddns.sh
    rm -rf "$INSTALL_DIR" "$LOG_FILE"
    ok "卸载完成"
    pause
}

#========================================================
# 9. 关于
#========================================================
about(){
    title "关于"
    echo ""
    echo "   ${BOLD}${PINK}❀ ${AUTHOR} · Cloudflare DDNS${NC}"
    echo "   ${DIM}动态域名管理台  v${VERSION}${NC}"
    echo ""
    echo "   ${DIM}作者${NC}    ${AUTHOR}"
    echo "   ${DIM}功能${NC}    Cloudflare 动态解析，自动跟随公网 IP 变更"
    echo "   ${DIM}特性${NC}    单文件部署 · 中文域名 · 小黄云 / 灰云 · 换 IP 记录"
    echo "   ${DIM}菜单${NC}    ddns   或   bash $MENU_FILE"
    echo "   ${DIM}配置${NC}    $CONF_FILE"
    echo "   ${DIM}日志${NC}    $LOG_FILE"
    echo "   ${DIM}记录${NC}    $CHANGE_LOG"
    echo ""
    echo "   ${DIM}声明${NC}    仅供个人学习与自用，请遵守 Cloudflare 服务条款"
    echo "   ${DIM}致谢${NC}    Cloudflare API 与所有开源脚本作者"
    echo ""
    pause
}

#========================================================
# 主菜单
#========================================================
while true; do
    clear
    echo ""
    echo "   ${DIM}${PINK}══════════════════════════════════════════════════════${NC}"
    echo "    ${BOLD}${PINK}❀  ${AUTHOR}  ·  Cloudflare DDNS${NC}"
    echo "    ${DIM}动态域名管理台  ·  v${VERSION}${NC}"
    echo "   ${DIM}${PINK}══════════════════════════════════════════════════════${NC}"
    echo ""

    if [ -f "$CONF_FILE" ]; then
        load_conf
        kv "域名" "${BOLD}${CYAN}${RECORD_DISPLAY:-$RECORD_NAME}${NC}"
        kv "区域" "${GREEN}${ZONE_NAME}${NC}"
        kv "代理" "$([ "$PROXIED" = "true" ] && echo "小黄云（隐藏源站）" || echo "灰云（仅 DNS）")   ${DIM}间隔${NC} ${INTERVAL:-300} 秒"
        kv "状态" "$(svc_state)"
    else
        kv "状态" "${YELLOW}尚未部署${NC}   ${DIM}bash ddns.sh 开始安装${NC}"
    fi

    echo ""
    hr
    echo ""
    echo "   ${GREEN}1${NC}  ${BOLD}运行状态${NC}      ${GREEN}5${NC}  ${BOLD}定时任务${NC}"
    echo "   ${GREEN}2${NC}  ${BOLD}日志记录${NC}      ${GREEN}6${NC}  ${BOLD}连通测试${NC}"
    echo "   ${GREEN}3${NC}  ${BOLD}立即执行${NC}      ${GREEN}7${NC}  ${BOLD}批量部署${NC}"
    echo "   ${GREEN}4${NC}  ${BOLD}修改配置${NC}      ${GREEN}8${NC}  ${BOLD}卸载程序${NC}"
    echo ""
    echo "   ${GREEN}0${NC}  ${BOLD}退出管理${NC}      ${GREEN}9${NC}  ${BOLD}关于作者${NC}"
    echo ""
    hr
    echo ""
    echo "   ${DIM}${PINK}❀${NC} ${DIM}${AUTHOR} 出品 · 作者 ${AUTHOR} · 仅供学习交流${NC}"
    echo ""
    read -rp "   请选择: " choice || exit 0

    case "$choice" in
        1) show_status ;;
        2) view_log ;;
        3) run_now ;;
        4) edit_conf ;;
        5) toggle_service ;;
        6) test_token ;;
        7) batch_deploy ;;
        8) uninstall ;;
        9) about ;;
        0) echo ""; ok "再见，${AUTHOR} DDNS 已退出"; echo ""; exit 0 ;;
        *) warn "无效选择"; sleep 1 ;;
    esac
done
MENU_EOF

chmod +x "$MENU_FILE"
}

#========================================================
# 生成运行脚本（含换IP记录）
#========================================================
write_runner(){
mkdir -p "$INSTALL_DIR"
cat > "$RUN_FILE" <<'RUN_EOF'
#!/bin/bash
# ❀ 桃花源 · Cloudflare DDNS 运行脚本（由 ddns.sh 自动生成，请勿手改）
CONF="/opt/cf-ddns/cf-ddns.conf"
LOG="/var/log/cf-ddns.log"
CHANGE_LOG="/opt/cf-ddns/ip-change.log"
API="https://api.cloudflare.com/client/v4"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log(){ echo "[$TS] $*" >> "$LOG"; }

[ -f "$CONF" ] || { log "配置文件缺失"; exit 1; }
source "$CONF"

# 兼容老配置：缺键时补默认值
TTL=${TTL:-60}
RECORD_TYPE=${RECORD_TYPE:-A}
PROXIED=${PROXIED:-false}

exec 200>/tmp/cf-ddns.lock
flock -n 200 2>/dev/null || exit 0

if [ -f "$LOG" ]; then
    SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
    if [ "$SZ" -gt 5242880 ]; then
        tail -1000 "$LOG" > "$LOG.tmp"
        mv "$LOG.tmp" "$LOG"
    fi
fi

get_ip(){
    local t m ip
    t=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --max-time 2 2>/dev/null)
    m=$(curl -s -H "X-aws-ec2-metadata-token: $t" --max-time 3 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    [ -z "$m" ] && m=$(curl -s --max-time 3 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    [[ "$m" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$m"; return 0; }
    for u in "https://api.ipify.org" "https://ifconfig.me/ip" \
             "https://ipv4.icanhazip.com" "https://ip.sb" "https://myip.ipip.net"; do
        ip=$(curl -4 -s --max-time 8 "$u" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -n "$ip" ] && { echo "$ip"; return 0; }
    done
    return 1
}

NEW_IP=$(get_ip)
[ -z "$NEW_IP" ] && { log "获取IP失败"; exit 1; }

RESP=$(curl -s --max-time 15 "$API/zones/$ZONE_ID/dns_records?type=$RECORD_TYPE&name=$RECORD_NAME" \
    -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
echo "$RESP" | grep -q '"success":true' || { log "API失败: $(echo "$RESP" | head -c 250)"; exit 1; }

RID=$(echo "$RESP" | grep -oE '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
OLD_IP=$(echo "$RESP" | grep -oE '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
OLD_PROX=$(echo "$RESP" | grep -oE '"proxied":(true|false)' | head -1 | sed 's/.*://')
OLD_TTL=$(echo "$RESP" | grep -oE '"ttl":[0-9]+' | head -1 | sed 's/.*://')

NAME_LOG="${RECORD_DISPLAY:-$RECORD_NAME}"
PXMODE=$([ "$PROXIED" = "true" ] && echo "小黄云" || echo "灰云")

# 小黄云下 TTL 由 Cloudflare 接管，提交 1（自动）；灰云才用自定义 TTL
NET_TTL="$TTL"
[ "$PROXIED" = "true" ] && NET_TTL=1

if [ -z "$RID" ]; then
    R=$(curl -s --max-time 15 -X POST "$API/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"$RECORD_TYPE\",\"name\":\"$RECORD_NAME\",\"content\":\"$NEW_IP\",\"ttl\":$NET_TTL,\"proxied\":$PROXIED}")
    if echo "$R" | grep -q '"success":true'; then
        log "创建 $NAME_LOG -> $NEW_IP （$PXMODE）"
        echo "$TS | 创建 | $NAME_LOG | (无) -> $NEW_IP | $PXMODE" >> "$CHANGE_LOG"
    else
        log "创建失败: $(echo "$R" | head -c 300)"
    fi
    exit 0
fi

# 需要更新的三种情况：IP 变了 / 代理模式变了 / 灰云下 TTL 变了
REASON=""
if [ "$NEW_IP" != "$OLD_IP" ]; then
    REASON="IP 变更"
fi
if [ "$OLD_PROX" != "$PROXIED" ]; then
    if [ -z "$REASON" ]; then REASON="代理变更"; else REASON="$REASON + 代理变更"; fi
fi
if [ "$PROXIED" != "true" ] && [ "$TTL" != "1" ] && [ -n "$OLD_TTL" ] && [ "$OLD_TTL" != "$TTL" ]; then
    if [ -z "$REASON" ]; then REASON="TTL 变更"; else REASON="$REASON + TTL 变更"; fi
fi

[ -z "$REASON" ] && { log "IP未变 $NAME_LOG = $NEW_IP"; exit 0; }

R=$(curl -s --max-time 15 -X PUT "$API/zones/$ZONE_ID/dns_records/$RID" \
    -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" \
    --data "{\"type\":\"$RECORD_TYPE\",\"name\":\"$RECORD_NAME\",\"content\":\"$NEW_IP\",\"ttl\":$NET_TTL,\"proxied\":$PROXIED}")

if echo "$R" | grep -q '"success":true'; then
    log "更新（$REASON）$NAME_LOG : $OLD_IP -> $NEW_IP （$PXMODE）"
    if [ "$NEW_IP" != "$OLD_IP" ]; then
        echo "$TS | 更换 | $NAME_LOG | $OLD_IP -> $NEW_IP | $PXMODE" >> "$CHANGE_LOG"
    fi
else
    log "更新失败: $(echo "$R" | head -c 300)"
fi
RUN_EOF

chmod +x "$RUN_FILE"
}

#========================================================
# 主流程
#========================================================
ALREADY=0
[ -f "$CONF_FILE" ] && ALREADY=1

banner "${AUTHOR} · Cloudflare DDNS" "动态域名一键部署 · v${VERSION}"

if [ "$ALREADY" -eq 1 ]; then
    warn "检测到本机已安装过 DDNS"
    echo ""
    source "$CONF_FILE" 2>/dev/null
    echo "   ${BOLD}${PEACH}当前配置${NC}"; hr
    kv "域名" "${BOLD}${CYAN}${RECORD_DISPLAY:-$RECORD_NAME}${NC}"
    kv "区域" "${GREEN}${ZONE_NAME}${NC}"
    kv "代理" "$([ "$PROXIED" = "true" ] && echo "小黄云（隐藏源站）" || echo "灰云（仅 DNS）")"
    kv "间隔" "${INTERVAL:-300} 秒"
    kv "缓存" "TTL ${TTL:-60} 秒$( [ "$PROXIED" = "true" ] && echo "（代理下 CF 固定 300 秒）" )"
    echo ""
    echo "   ${GREEN}1${NC}  重新配置（覆盖现有配置）"
    echo "   ${GREEN}2${NC}  保留配置，只修复菜单 / 运行脚本 / 快捷命令"
    echo "   ${GREEN}3${NC}  完全卸载后重装"
    echo "   ${GREEN}0${NC}  退出"
    echo ""
    read -rp "   请选择 [2]: " RC
    [ -z "$RC" ] && RC=2

    case "$RC" in
        0) echo ""; ok "已退出"; echo ""; exit 0 ;;
        2)
            msg "修复安装…"
            write_menu
            write_runner
            ok "菜单已重建：$MENU_FILE"
            ok "运行脚本已重建：$RUN_FILE"

            ln -sf "$MENU_FILE" /usr/local/bin/ddns 2>/dev/null
            chmod +x "$MENU_FILE" /usr/local/bin/ddns 2>/dev/null
            if ! grep -q "alias ddns=" ~/.bashrc 2>/dev/null; then
                echo "" >> ~/.bashrc
                echo "# ❀ 桃花源 · Cloudflare DDNS 菜单" >> ~/.bashrc
                echo "alias ddns='bash $MENU_FILE'" >> ~/.bashrc
            fi
            echo "alias ddns='bash $MENU_FILE'" > /etc/profile.d/cf-ddns.sh
            chmod 644 /etc/profile.d/cf-ddns.sh

            ensure_schedule "${INTERVAL:-300}"

            FIRST=$(head -1 "$MENU_FILE")
            echo ""
            if [ "$FIRST" = "#!/bin/bash" ]; then
                ok "菜单文件校验通过"
            else
                err "菜单文件首行异常：$FIRST"
            fi

            echo ""
            hr
            echo ""
            echo "   ${BOLD}${GREEN}✓ 修复完成${NC}"
            echo ""
            echo "   ${GREEN}★${NC} 输入 ${BOLD}ddns${NC} 打开菜单"
            echo "   ${DIM}或：bash $MENU_FILE${NC}"
            echo ""
            ls -l "$MENU_FILE" /usr/local/bin/ddns 2>/dev/null
            echo ""
            exit 0
            ;;
        3)
            warn "卸载现有安装…"
            systemctl disable --now cf-ddns.timer 2>/dev/null
            rm -f /etc/systemd/system/cf-ddns.service /etc/systemd/system/cf-ddns.timer
            systemctl daemon-reload 2>/dev/null
            crontab -l 2>/dev/null | grep -v "cf-ddns-run.sh" | crontab - 2>/dev/null
            rm -rf "$INSTALL_DIR" "$LOG_FILE"
            ok "已卸载，开始全新安装"; echo ""
            ;;
        *) warn "无效选择"; exit 0 ;;
    esac
fi

#========================================================
# 全新安装
#========================================================
if [ -n "$CF_TOKEN" ]; then
    TOKEN="$CF_TOKEN"
    msg "使用环境变量 Token"
else
    echo "   请粘贴 Cloudflare API Token（输入时明文显示）："
    read -rp "   Token: " TOKEN
fi
TOKEN=$(echo "$TOKEN" | tr -d '[:space:]')
[ -z "$TOKEN" ] && { err "Token 不能为空"; exit 1; }
echo "   ${GREEN}✓${NC} Token 已接收（${#TOKEN} 位）"
echo ""

if [ -n "$CF_DOMAIN" ]; then
    FULL_DOMAIN="$CF_DOMAIN"
    msg "使用环境变量域名：$FULL_DOMAIN"
else
    echo "   请输入节点域名（中文或 punycode 均可）："
    read -rp "   域名: " FULL_DOMAIN
fi
FULL_DOMAIN=$(echo "$FULL_DOMAIN" | tr -d '[:space:]' | sed 's#^https\?://##; s#/.*$##')
FULL_DOMAIN=$(printf '%s' "$FULL_DOMAIN" | tr 'A-Z' 'a-z')
[ -z "$FULL_DOMAIN" ] && { err "域名不能为空"; exit 1; }
echo ""

echo "   代理模式："
echo "   ${GREEN}1${NC}  小黄云（隐藏源站，ws+tls 节点）   ${DIM}默认${NC}"
echo "   ${GREEN}2${NC}  灰云（源站公开，hysteria2 / tuic / reality）"
read -rp "   请选择 [1]: " PX
[ -z "$PX" ] && PX=1
if [ "$PX" = "1" ]; then PROXIED="true"; PX_NAME="小黄云"; else PROXIED="false"; PX_NAME="灰云"; fi

echo ""
read -rp "   检测间隔秒数 [300]: " INTV
[ -z "$INTV" ] && INTV=300
if ! echo "$INTV" | grep -qE '^[0-9]+$' || [ "$INTV" -lt 60 ]; then
    warn "需 >= 60 秒，重置为 300"; INTV=300
fi

echo ""
msg "验证 Token..."

if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else err "需要 python3"; exit 1; fi

ZONES_JSON=$(curl -s --max-time 20 "$API/zones?per_page=50" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
if ! echo "$ZONES_JSON" | grep -q '"success":true'; then
    err "Token 无效或网络不通"
    echo "   ${RED}$(echo "$ZONES_JSON" | head -c 400)${NC}"
    exit 1
fi

ZONE_RESULT=$(echo "$ZONES_JSON" | FULL_DOMAIN="$FULL_DOMAIN" $PY -c "
import sys, json, os
try:
    import idna
except ImportError:
    idna = None
def A(d):
    if not d: return d
    if d.isascii(): return d.lower()
    try:
        if idna: return idna.encode(d).decode('ascii').lower()
        return d.encode('idna').decode('ascii').lower()
    except Exception:
        return d.lower()
d = json.load(sys.stdin)
zones = d.get('result') or []
target = A(os.environ.get('FULL_DOMAIN','').strip())
if not zones:
    print('EMPTY||||'); sys.exit(0)
best = None
allz = []
for z in zones:
    n = z.get('name') or ''
    if not n: continue
    na = A(n); allz.append(n)
    if target == na or target.endswith('.' + na):
        if best is None or len(na) > len(best.get('a','')):
            best = {'id': z['id'], 'n': n, 'a': na}
if best:
    print(best['id'] + '|' + best['n'] + '|' + best['a'] + '|' + ';;'.join(allz))
else:
    print('NOTFOUND||||' + ';;'.join(allz))
")

ZONE_ID=$(echo "$ZONE_RESULT" | cut -d'|' -f1)
ZONE_NAME=$(echo "$ZONE_RESULT" | cut -d'|' -f2)
ZONE_ASCII=$(echo "$ZONE_RESULT" | cut -d'|' -f3)
ZONE_LIST=$(echo "$ZONE_RESULT" | cut -d'|' -f4)

case "$ZONE_ID" in
    EMPTY) err "Token 未授权任何域名"; exit 1 ;;
    NOTFOUND)
        err "域名 ${BOLD}$FULL_DOMAIN${NC} 不属于 Token 可访问的任何 Zone"
        echo ""
        echo "   Token 可见域名："
        echo "$ZONE_LIST" | tr ';' '\n' | while read -r z; do
            [ -n "$z" ] && echo "     ${CYAN}- $z${NC}"
        done
        exit 1
        ;;
esac

ok "域名校验通过"
echo ""
kv "域名" "${BOLD}${CYAN}$FULL_DOMAIN${NC}"
kv "区域" "${GREEN}$ZONE_NAME${NC}"
kv "标识" "$ZONE_ID"

echo ""
msg "检测本机公网 IP…"
NEW_IP=""
T=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --max-time 2 2>/dev/null)
M=$(curl -s -H "X-aws-ec2-metadata-token: $T" --max-time 3 \
    http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
[ -z "$M" ] && M=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
if [[ "$M" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    NEW_IP="$M"; ok "云元数据 IP：$NEW_IP"
fi
if [ -z "$NEW_IP" ]; then
    for u in "https://api.ipify.org" "https://ifconfig.me/ip" \
             "https://ipv4.icanhazip.com" "https://ip.sb"; do
        ip=$(curl -4 -s --max-time 8 "$u" 2>/dev/null \
             | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -n "$ip" ] && { NEW_IP="$ip"; break; }
    done
fi
[ -z "$NEW_IP" ] && { err "无法获取公网 IP"; exit 1; }
ok "本机公网 IP：${BOLD}${GREEN}$NEW_IP${NC}"

mkdir -p "$INSTALL_DIR"
DOMAIN_ASCII=$(FULL_DOMAIN="$FULL_DOMAIN" $PY -c "
import os
d = os.environ.get('FULL_DOMAIN','')
if d.isascii():
    print(d.lower())
else:
    try:
        import idna; print(idna.encode(d).decode('ascii'))
    except Exception:
        try: print(d.encode('idna').decode('ascii'))
        except Exception: print(d)
")

cat > "$CONF_FILE" <<CONF
# ❀ 桃花源 · Cloudflare DDNS 配置 - $(date '+%Y-%m-%d %H:%M:%S')
API_TOKEN="$TOKEN"
ZONE_ID="$ZONE_ID"
ZONE_NAME="$ZONE_NAME"
RECORD_NAME="$DOMAIN_ASCII"
RECORD_DISPLAY="$FULL_DOMAIN"
RECORD_TYPE="A"
PROXIED="$PROXIED"
TTL=60
INTERVAL="$INTV"
CONF

chmod 600 "$CONF_FILE"
ok "配置已保存：$CONF_FILE"

echo ""
msg "生成菜单与运行脚本…"
write_menu
ok "菜单：$MENU_FILE"
write_runner
ok "运行脚本：$RUN_FILE"

echo ""
msg "首次执行…"
bash "$RUN_FILE"
sleep 1
[ -f "$LOG_FILE" ] && tail -1 "$LOG_FILE" | sed 's/^/   /'

echo ""
msg "配置定时任务（每 ${INTV} 秒）…"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    cat > /etc/systemd/system/cf-ddns.service <<EOF
[Unit]
Description=Cloudflare DDNS (桃花源)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash $RUN_FILE
EOF
    cat > /etc/systemd/system/cf-ddns.timer <<EOF
[Unit]
Description=Cloudflare DDNS Timer (桃花源)
[Timer]
OnBootSec=30s
OnUnitActiveSec=${INTV}s
AccuracySec=5s
Unit=cf-ddns.service
[Install]
WantedBy=timers.target
EOF
fi
ensure_schedule "$INTV"

echo ""
msg "安装快捷命令…"
ln -sf "$MENU_FILE" /usr/local/bin/ddns 2>/dev/null && ok "已创建 /usr/local/bin/ddns"
if ! grep -q "alias ddns=" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# ❀ 桃花源 · Cloudflare DDNS 菜单" >> ~/.bashrc
    echo "alias ddns='bash $MENU_FILE'" >> ~/.bashrc
fi
echo "alias ddns='bash $MENU_FILE'" > /etc/profile.d/cf-ddns.sh
chmod 644 /etc/profile.d/cf-ddns.sh
ok "别名已写入 ~/.bashrc 与 /etc/profile.d/"

echo ""
echo "   ${GREEN}══════════════════════════════════════════════════════${NC}"
echo "    ${BOLD}${GREEN}✓  部署完成${NC}"
echo "    ${DIM}${AUTHOR} · Cloudflare DDNS  ·  v${VERSION}${NC}"
echo "   ${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
kv "域名" "${BOLD}${CYAN}$FULL_DOMAIN${NC}"
[ "$DOMAIN_ASCII" != "$FULL_DOMAIN" ] && kv "编码" "${DOMAIN_ASCII}   （punycode）"
kv "区域" "${GREEN}$ZONE_NAME${NC}"
kv "当前" "${CYAN}$NEW_IP${NC}"
kv "代理" "$PX_NAME"
kv "间隔" "${INTV} 秒"
kv "缓存" "TTL 60 秒$( [ "$PROXIED" = "true" ] && echo "（代理下 CF 固定 300 秒）" )"
echo ""
kv "配置" "$CONF_FILE"
kv "日志" "$LOG_FILE"
kv "记录" "$CHANGE_LOG"
echo ""
echo "   ${BOLD}${PINK}★${NC} 输入 ${BOLD}ddns${NC} 打开管理菜单"
echo "   ${DIM}提示找不到命令时：source ~/.bashrc 或 hash -r${NC}"
echo "   ${DIM}也可直接：bash $MENU_FILE${NC}"
echo ""
echo "   ${DIM}${PINK}❀ ${AUTHOR} 出品 · 作者 ${AUTHOR}${NC}"
echo ""
