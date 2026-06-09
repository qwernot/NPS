### Dark's NPS 一键部署脚本
# 在新 Linux 系统运行即可自动部署 Docker 和本项目

set -e
VERSION="0.26.32"
NPS_IMAGE="darkver8/nps:latest"
NPS_DIR="/opt/darks-nps"
CONF_DIR="$NPS_DIR/conf"
LOG_FILE="/var/log/nps-install.log"

# ─── 颜色输出 ───
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

msg() { printf "${G}[+]${NC} %s\n" "$1" }
warn() { printf "${Y}[!]${NC} %s\n" "$1" }
err() { printf "${R}[-]${NC} %s\n" "$1"; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true; }

# ─── 权限检查 ───
if [[ $EUID -ne 0 ]]; then
    err "请使用 root 用户或 sudo 运行此脚本"
    exit 1
fi

log "开始安装 NPS $VERSION"
msg "Dark's NPS 一键部署脚本"
echo "版本: $VERSION"
echo "日志: $LOG_FILE"
echo ""

# ─── 0. 系统信息 ───
msg "检测系统信息..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "  发行版: $PRETTY_NAME ($ID)"
    echo "  内核: $(uname -r)"
    log "系统: $PRETTY_NAME"
else
    echo "  发行版: $(cat /etc/issue 2>/dev/null || echo 'unknown')"
    echo "  内核: $(uname -r)"
    log "系统: unknown"
fi

# ─── 1. 检测是否已安装 Docker ───
msg "检测 Docker 安装..."
if command -v docker &>/dev/null && docker --version &>/dev/null; then
    echo "  Docker 已安装: $(docker --version)"
else
    echo "  Docker 未安装，正在安装..."
    # 卸载旧版本（避免冲突）
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y "$pkg" 2>/dev/null || true
    done

    # 安装依赖
    msg "安装 Docker 依赖..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    # 添加 Docker 官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker 仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    msg "安装 Docker Engine..."
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin 2>/dev/null

    # 启动 Docker
    if systemctl is-active --quiet docker; then
        systemctl restart docker
    else
        dockerd &>/dev/null &
        sleep 3
    fi

    # 设置开机自启
    systemctl enable docker 2>/dev/null || true

    echo "  Docker 安装完成: $(docker --version)"
    log "Docker 安装完成"
fi

# ─── 2. 创建目录 ───
msg "创建目录结构..."
mkdir -p "$CONF_DIR"
mkdir -p /var/log/nps

# ─── 3. 检查配置文件 ───
if [[ ! -f "$CONF_DIR/nps.conf" ]]; then
    msg "生成默认配置文件..."
    cat > "$CONF_DIR/nps.conf" << 'CONF_EOF'
appname = nps
runmode = dev

# HTTP(S) proxy port
http_proxy_ip=0.0.0.0
http_proxy_port=80
https_proxy_port=443
https_just_proxy=true
https_default_cert_file=conf/server.pem
https_default_key_file=conf/server.key

# bridge
bridge_type=tcp
bridge_port=8024
bridge_ip=0.0.0.0

# public vkey for client registration
public_vkey=123

# traffic data persistence
flow_store_interval=1

# log
log_level=6
log_path=/var/log/nps/nps.log

# web admin
web_host=0.0.0.0
web_username=admin
web_password=123
web_port=8081
web_ip=0.0.0.0
web_base_url=
web_open_ssl=false
web_cert_file=conf/server.pem
web_key_file=conf/server.key

auth_key=123
auth_crypt_key=213

# allow_user_login: enable multi-user
allow_user_login=true
allow_user_register=false
allow_user_change_username=true

# extensions
allow_flow_limit=true
allow_rate_limit=true
allow_tunnel_num_limit=true
allow_local_proxy=false
allow_connection_num_limit=true
allow_multi_ip=true
system_info_display=true
http_add_origin_header=true

http_cache=false
http_cache_length=100

disconnect_timeout=60
open_captcha=false

# tls
tls_enable=true
tls_bridge_port=8025
CONF_EOF

    echo "  配置文件: $CONF_DIR/nps.conf"
else
    echo "  配置文件已存在: $CONF_DIR/nps.conf"
fi

# ─── 4. 准备证书（如果没有） ───
if [[ ! -f "$CONF_DIR/server.pem" || ! -f "$CONF_DIR/server.key" ]]; then
    msg "生成自签名 HTTPS 证书..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CONF_DIR/server.key" \
        -out "$CONF_DIR/server.pem" \
        -subj "/CN=nps" 2>/dev/null
    echo "  证书已生成: $CONF_DIR/server.pem, $CONF_DIR/server.key"
fi

# ─── 5. 拉取镜像 ───
msg "拉取 Docker 镜像 $NPS_IMAGE..."
if docker image inspect "$NPS_IMAGE" &>/dev/null; then
    echo "  镜像已存在，跳过拉取"
else
    docker pull "$NPS_IMAGE"
    echo "  镜像拉取完成"
fi

# ─── 6. 清理旧容器 ───
if docker ps -a --format '{{.Names}}' | grep -q '^nps$'; then
    msg "停止并移除旧容器..."
    docker stop nps 2>/dev/null || true
    docker rm nps 2>/dev/null || true
fi

# ─── 7. 启动容器 ───
msg "启动 NPS 容器..."
docker run -d \
    --name nps \
    --restart unless-stopped \
    --network host \
    -v "$CONF_DIR:/conf" \
    -v /var/log/nps:/var/log/nps \
    "$NPS_IMAGE"

echo "  容器已启动: nps"
log "容器启动完成"

# ─── 8. 验证 ───
echo ""
msg "等待服务启动..."
sleep 3

# 检查容器状态
if ! docker ps --format '{{.Names}}' | grep -q '^nps$'; then
    err "容器启动失败，查看日志："
    docker logs --tail=20 nps
    exit 1
fi

# 检查端口
echo "  监听端口:"
for port in 80 443 8024 8025 8081; do
    if ss -ltnp 2>/dev/null | grep -q ":$port " || netstat -ltnp 2>/dev/null | grep -q ":$port "; then
        echo "    端口 $port: 已监听"
    else
        warn "端口 $port: 未检测到（可能需等待服务完全启动）"
    fi
done

# 检查 Web
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://127.0.0.1:8081/login/index 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    msg "Web 管理后台响应正常 (HTTP $HTTP_CODE)"
else
    warn "Web 管理后台尚未响应 (HTTP $HTTP_CODE)，可能正在启动中"
    log "Web 响应码: $HTTP_CODE"
fi

# ─── 完成 ───
echo ""
echo "================================================================"
echo -e " ${G}✅ NPS 部署完成${NC}"
echo "================================================================"
echo ""
echo -e " ${C}管理后台:${NC} http://$(hostname -I 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo '服务器IP'):8081/login/index"
echo -e " ${C}默认账号:${NC} admin"
echo -e " ${C}默认密码:${NC} 123"
echo ""
echo -e " ${Y}⚠️ 重要:${NC} 请立即修改默认密码！"
echo "  修改方式: 登录后台 → 系统 → 修改密码"
echo ""
echo -e " ${C}配置文件:${NC} $CONF_DIR/nps.conf"
echo -e " ${C}容器名称:${NC} nps"
echo ""
echo "常用命令:"
echo "  查看状态:     docker ps --filter name=nps"
echo "  查看日志:     docker logs -f nps"
echo "  重启容器:     docker restart nps"
echo "  更新镜像:     docker pull $NPS_IMAGE && docker rm -f nps && (同上启动命令)"
echo ""
echo -e " ${Y}⚠️ 请确认防火墙/安全组已放行以下端口:${NC}"
echo "    8081  - Web 管理后台"
echo "    80    - HTTP 代理"
echo "    443   - HTTPS 代理"
echo "    8024  - NPC 默认连接端口"
echo "    8025  - NPC TLS 连接端口"
echo "    (你的端口池范围)"
echo ""
echo "================================================================"
log "部署完成，请访问 http://<IP>:8081/login/index"
