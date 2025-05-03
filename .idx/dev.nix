# 要了解更多关于如何使用 Nix 配置您的环境
# 请参阅：https://firebase.google.com/docs/studio/customize-workspace
{ pkgs, ... }: {
  # 系统环境变量
  env = {
    # Sing-box 配置
    ARGO_DOMAIN = "your-domain.example.com";
    UUID = "de04add9-5c68-8bab-950c-08cd5320df18";
    CDN = "your-cdn-domain.com";
    NODE_NAME = "your-node-name";
    VMESS_PORT = "";  # 端口范围 1000-65535
    VLESS_PORT = "";  # 端口范围 1000-65535

    # 节点信息的 Nginx 静态文件服务
    NGINX_PORT = "";  # 端口范围 1000-65535

    # Argo Tunnel 配置
    ARGO_TOKEN = "your-argo-token";

    # Nezha 监控配置
    NEZHA_SERVER = "monitor.example.com";
    NEZHA_PORT = "443";
    NEZHA_KEY = "your-nezha-key";
    NEZHA_TLS = "--tls";  # 不要可以清空值

    # SSH 配置
    SSH_PASSWORD = "your-secure-password";

    # FRP 配置
    FRP_SERVER_ADDR = "frp.example.com";
    FRP_SERVER_PORT = "7000";
    FRP_AUTH_TOKEN = "your-frp-token";

    # 远程端口配置
    DEBIAN_REMOTE_PORT = "6001";
    UBUNTU_REMOTE_PORT = "6002";
    CENTOS_REMOTE_PORT = "6003";
    ALPINE_REMOTE_PORT = "6004";
  };

  # 使用哪个 nixpkgs 频道
  channel = "stable-24.11"; # 或 "unstable"

  # 添加常用系统工具包
  packages = [
    # 基础系统工具
    pkgs.debianutils        # Debian 系统实用工具集
    pkgs.uutils-coreutils-noprefix  # Rust 实现的核心工具集
    pkgs.gnugrep            # GNU 文本搜索工具
    pkgs.openssl            # SSL/TLS 加密工具
    pkgs.screen             # 终端多窗口管理器
    pkgs.qrencode           # 二维码生成工具

    # 系统监控和管理
    pkgs.procps             # 进程监控工具集（ps, top 等）
    pkgs.nettools           # 网络配置工具集
    pkgs.rsync              # 文件同步工具
    pkgs.psmisc             # 进程管理工具集（killall, pstree 等）
    pkgs.htop               # 交互式进程查看器
    pkgs.iotop              # IO 监控工具

    # 开发工具
    pkgs.gcc                # GNU C/C++ 编译器
    pkgs.gnumake            # GNU 构建工具
    pkgs.cmake              # 跨平台构建系统
    pkgs.python3            # Python 3 编程语言
    pkgs.openssh            # SSH 连接工具
    pkgs.nano               # 简单文本编辑器

    # 文件工具
    pkgs.file               # 文件类型识别工具
    pkgs.tree               # 目录树显示工具
    pkgs.zip                # 文件压缩工具

    # 网络代理工具
    pkgs.cloudflared        # Cloudflare 隧道客户端
    pkgs.xray               # 代理工具
    pkgs.sing-box           # 通用代理平台
  ];

  # 服务配置
  services = {
    # 启用 Docker 服务
    docker.enable = true;
  };

  idx = {
    # 搜索扩展程序: https://open-vsx.org/ 并使用 "publisher.id"
    extensions = [
      # 添加您需要的扩展
    ];

    # 启用预览
    previews = {
      enable = true;
      previews = {
        # 预览配置
      };
    };

    # 工作区生命周期钩子
    workspace = {
      # 工作区首次创建时运行
      onCreate = {
        default.openFiles = [ ".idx/dev.nix" "README.md" ];
      };

      # 工作区(重新)启动时运行
      onStart = {
        # 创建配置文件目录
        init-01-mkdir = "[ -d conf ] || mkdir conf; [ -d conf ] || mkdir sing-box";

        # 检查并下载 Nezha Agent
        init-02-nezha = "[ -f conf/nezha-agent ] || (wget -O nezha-agent.zip https://github.com/nezhahq/agent/releases/download/v0.20.5/nezha-agent_linux_amd64.zip && unzip nezha-agent.zip -d conf && rm nezha-agent.zip)";

        # 检查并创建 nginx 配置
        init-02-nginx = "cat > nginx.conf << EOF
user  nginx;
worker_processes  auto;

error_log  /dev/null;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    charset utf-8;

    access_log  /dev/null;

    sendfile        on;

    keepalive_timeout  65;

    #gzip  on;

    server {
        listen       $NGINX_PORT;
        server_name  localhost;

        # 严格匹配 /\$UUID/node 路径
        location = /\$UUID/node {
            alias   /data/node.txt;
            default_type text/plain;
            charset utf-8;
            add_header Content-Type 'text/plain; charset=utf-8';
        }

        # 拒绝其他所有请求
        location / {
            return 403;
        }

        # 错误页面配置
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
}
EOF";

        # 检查并创建 SSL 证书
        init-02-ssl-cert = "[ -f sing-box/cert/private.key ] || (mkdir -p sing-box/cert && openssl ecparam -genkey -name prime256v1 -out sing-box/cert/private.key && openssl req -new -x509 -days 36500 -key sing-box/cert/private.key -out sing-box/cert/cert.pem -subj \"/CN=$(awk -F . '{print $(NF-1)\".\"$NF}' <<< \"$ARGO_DOMAIN\")\")";

        # 检查并创建 sing-box 配置
        init-02-singbox = "cat > config.json << EOF
{
    \"dns\":{
        \"servers\":[
            {
                \"type\":\"local\"
            }
        ],
        \"strategy\": \"ipv4_only\"
    },
    \"experimental\": {
        \"cache_file\": {
            \"enabled\": true,
            \"path\": \"/etc/sing-box/cache.db\"
        }
    },
    \"ntp\": {
        \"enabled\": true,
        \"server\": \"time.apple.com\",
        \"server_port\": 123,
        \"interval\": \"60m\"
    },
    \"inbounds\": [
        {
            \"type\":\"vmess\",
            \"tag\":\"vmess-in\",
            \"listen\":\"::\",
            \"listen_port\":$VMESS_PORT,
            \"tcp_fast_open\":false,
            \"proxy_protocol\":false,
            \"users\":[
                {
                    \"uuid\":\"$UUID\",
                    \"alterId\":0
                }
            ],
            \"transport\":{
                \"type\":\"ws\",
                \"path\":\"/$UUID-vmess\",
                \"max_early_data\":2048,
                \"early_data_header_name\":\"Sec-WebSocket-Protocol\"
            },
            \"tls\": {
                \"enabled\": true,
                \"server_name\": \"$ARGO_DOMAIN\",
                \"certificate_path\": \"/etc/sing-box/cert/cert.pem\",
                \"key_path\": \"/etc/sing-box/cert/private.key\"
            },
            \"multiplex\":{
                \"enabled\":true,
                \"padding\":true,
                \"brutal\":{
                    \"enabled\":false,
                    \"up_mbps\":1000,
                    \"down_mbps\":1000
                }
            }
        },
        {
            \"type\": \"vless\",
            \"tag\": \"vless-in\",
            \"listen\": \"::\",
            \"listen_port\": $VLESS_PORT,
            \"users\": [
                {
                    \"uuid\": \"$UUID\",
                    \"flow\": \"\"
                }
            ],
            \"transport\": {
                \"type\": \"ws\",
                \"path\": \"/$UUID-vless\",
                \"max_early_data\": 2048,
                \"early_data_header_name\": \"Sec-WebSocket-Protocol\"
            },
            \"tls\": {
                \"enabled\": true,
                \"server_name\": \"$ARGO_DOMAIN\",
                \"certificate_path\": \"/etc/sing-box/cert/cert.pem\",
                \"key_path\": \"/etc/sing-box/cert/private.key\"
            },
            \"multiplex\": {
                \"enabled\":true,
                \"padding\":true
            }
        }
    ],
    \"outbounds\": [
        {
            \"type\": \"direct\",
            \"tag\": \"direct\"
        }
    ]
}
EOF

          # 创建 node.txt 文件
          cat > node.txt << EOF
浏览器访问节点信息: https://$ARGO_DOMAIN/$UUID/node

-------------------------------------

V2RayN:

vmess://\$(echo -n '{\"v\":\"2\",\"ps\":\"'$NODE_NAME' vmess\",\"add\":\"'$CDN'\",\"port\":\"443\",\"id\":\"'$UUID'\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"'$ARGO_DOMAIN'\",\"path\":\"/'$UUID'-vmess\",\"tls\":\"tls\",\"sni\":\"'$ARGO_DOMAIN'\",\"alpn\":\"\",\"fp\":\"chrome\"}' | base64 -w0)

vless://$UUID@$CDN:443?encryption=none&security=tls&sni=$ARGO_DOMAIN&fp=chrome&type=ws&host=$ARGO_DOMAIN&path=%2F$UUID-vless#$NODE_NAME%20vless

-------------------------------------

NekoBox:

vmess://\$(echo -n '{\"add\":\"'$CDN'\",\"aid\":\"0\",\"host\":\"'$ARGO_DOMAIN'\",\"id\":\"'$UUID'\",\"net\":\"ws\",\"path\":\"/'$UUID'-vmess\",\"port\":\"443\",\"ps\":\"'$NODE_NAME' vmess\",\"scy\":\"none\",\"sni\":\"'$ARGO_DOMAIN'\",\"tls\":\"tls\",\"type\":\"\",\"v\":\"2\"}' | base64 -w0)

vless://$UUID@$CDN:443?security=tls&sni=$ARGO_DOMAIN&fp=chrome&type=ws&path=/$UUID-vless&host=$ARGO_DOMAIN&encryption=none#$NODE_NAME%20vless

-------------------------------------

Shadowrocket:

vmess://\$(echo -n \"none:$UUID@$CDN:443\" | base64 -w0)?remarks=$NODE_NAME%20vmess&obfsParam=%7B%22Host%22:%22$ARGO_DOMAIN%22%7D&path=/$UUID-vmess?ed=2048&obfs=websocket&tls=1&peer=$ARGO_DOMAIN&mux=1&alterId=0

vless://\$(echo -n \"auto:$UUID@$CDN:443\" | base64 -w0)?remarks=$NODE_NAME%20vless&obfsParam=%7B%22Host%22:%22$ARGO_DOMAIN%22%7D&path=/$UUID-vless?ed=2048&obfs=websocket&tls=1&peer=$ARGO_DOMAIN&allowInsecure=1&mux=1

-------------------------------------

Clash:

proxies:
  - name: \"$NODE_NAME vmess\"
    type: vmess
    server: \"$CDN\"
    port: 443
    uuid: \"$UUID\"
    alterId: 0
    cipher: none
    tls: true
    servername: \"$ARGO_DOMAIN\"
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: \"/$UUID-vmess\"
      headers:
        Host: \"$ARGO_DOMAIN\"
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
    smux:
      enabled: true
      protocol: 'h2mux'
      padding: true
      max-connections: '8'
      min-streams: '16'
      statistic: true
      only-tcp: false
    tfo: false

  - name: \"$NODE_NAME vless\"
    type: vless
    server: \"$CDN\"
    port: 443
    uuid: \"$UUID\"
    tls: true
    servername: \"$ARGO_DOMAIN\"
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: \"/$UUID-vless\"
      headers:
        Host: \"$ARGO_DOMAIN\"
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
    smux:
      enabled: true
      protocol: 'h2mux'
      padding: true
      max-connections: '8'
      min-streams: '16'
      statistic: true
      only-tcp: false
    tfo: false

-------------------------------------

SingBox:

{
    \"outbounds\": [
        {
            \"tag\": \"$NODE_NAME vmess\",
            \"type\": \"vmess\",
            \"server\": \"$CDN\",
            \"server_port\": 443,
            \"uuid\": \"$UUID\",
            \"alter_id\": 0,
            \"security\": \"none\",
            \"network\": \"tcp\",
            \"tcp_fast_open\": false,
            \"transport\": {
                \"type\": \"ws\",
                \"path\": \"/$UUID-vmess\",
                \"headers\": {
                    \"Host\": \"$ARGO_DOMAIN\"
                }
            },
            \"tls\": {
                \"enabled\": true,
                \"insecure\": false,
                \"server_name\": \"$ARGO_DOMAIN\",
                \"utls\": {
                    \"enabled\": true,
                    \"fingerprint\": \"chrome\"
                }
            },
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_streams\": 16,
                \"padding\": true
            }
        },
        {
            \"type\": \"vless\",
            \"tag\": \"$NODE_NAME vless\",
            \"server\": \"$CDN\",
            \"server_port\": 443,
            \"uuid\": \"$UUID\",
            \"network\": \"tcp\",
            \"tcp_fast_open\": false,
            \"tls\": {
                \"enabled\": true,
                \"insecure\": false,
                \"server_name\": \"$ARGO_DOMAIN\",
                \"utls\": {
                    \"enabled\": true,
                    \"fingerprint\": \"chrome\"
                }
            },
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_streams\": 16,
                \"padding\": true
            }
        }
    ]
}
EOF
        # 把所有的配置文件移到 sing-box 工作目录
        rm -rf sing-box/{nginx.conf,config.json,node.txt}
        mv nginx.conf config.json node.txt sing-box/";

        # 检查并创建 docker compose 配置文件
        init-02-compose = "cat > docker-compose.yml << 'EOF'
services:
  debian:
    image: debian:latest
    container_name: debian
    hostname: debian
    networks:
      - idx
    volumes:
      - debian_data:/data
    tty: true
    restart: unless-stopped
    command: |
      bash -c \"
        export DEBIAN_FRONTEND=noninteractive &&
        apt update && apt install -y openssh-server iproute2 &&
        echo \"root:$SSH_PASSWORD\" | chpasswd &&
        sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
        sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
        mkdir -p /var/run/sshd &&
        service ssh start &&
        tail -f /dev/null
      \"

  ubuntu:
    image: ubuntu:latest
    container_name: ubuntu
    hostname: ubuntu
    networks:
      - idx
    volumes:
      - ubuntu_data:/data
    tty: true
    restart: unless-stopped
    command: |
      bash -c \"
        export DEBIAN_FRONTEND=noninteractive &&
        apt update && apt install -y openssh-server &&
        echo \"root:$SSH_PASSWORD\" | chpasswd &&
        sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
        sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
        mkdir -p /var/run/sshd &&
        service ssh start &&
        tail -f /dev/null
      \"

  centos9:
    image: quay.io/centos/centos:stream9
    container_name: centos9
    hostname: centos9
    networks:
      - idx
    volumes:
      - centos9_data:/data
    tty: true
    restart: unless-stopped
    command: |
      sh -c \"
        dnf install -y openssh-server passwd iproute procps-ng &&
        echo \"root:$SSH_PASSWORD\" | chpasswd &&
        mkdir -p /run/sshd &&
        ssh-keygen -A &&
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
        /usr/sbin/sshd -D &
        tail -f /dev/null
      \"

  alpine:
    image: alpine:latest
    container_name: alpine
    hostname: alpine
    networks:
      - idx
    volumes:
      - alpine_data:/data
    tty: true
    restart: unless-stopped
    command: |
      sh -c \"
        apk update && apk add --no-cache openssh-server openssh-sftp-server &&
        echo \"root:$SSH_PASSWORD\" | chpasswd &&
        sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
        sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
        mkdir -p /run/sshd &&
        ssh-keygen -A &&
        /usr/sbin/sshd &&
        tail -f /dev/null
      \"

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: tunnel --edge-ip-version auto run --token $ARGO_TOKEN
    networks:
      - idx
    volumes:
      - cloudflared_data:/etc/cloudflared
    restart: unless-stopped

  frpc:
    image: snowdreamtech/frpc
    container_name: frpc
    networks:
      - idx
    volumes:
      - ./conf/frpc.toml:/frp/frpc.toml
    command: -c /frp/frpc.toml
    restart: unless-stopped

  sing-box:
    image: fscarmen/sing-box:pre
    container_name: sing-box
    networks:
      - idx
    volumes:
      - ./sing-box:/etc/sing-box
    command: run -c /etc/sing-box/config.json
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: nginx
    networks:
      - idx
    volumes:
      - ./sing-box/node.txt:/data/node.txt:ro
      - ./sing-box/nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped

  nezha-agent:
    image: fscarmen/nezha-agent:latest
    container_name: nezha-agent
    pid: host        # 使用主机 PID 命名空间
    volumes:
      - /:/host:ro     # 挂载主机根目录
      - /proc:/host/proc:ro  # 挂载主机进程信息
      - /sys:/host/sys:ro    # 挂载主机系统信息
      - /etc:/host/etc:ro    # 挂载主机配置
    environment:
      - NEZHA_SERVER=$NEZHA_SERVER
      - NEZHA_PORT=$NEZHA_PORT
      - NEZHA_KEY=$NEZHA_KEY
      - NEZHA_TLS=$NEZHA_TLS
    command: -s $NEZHA_SERVER:$NEZHA_PORT -p $NEZHA_KEY $NEZHA_TLS
    restart: unless-stopped

networks:
  idx:
    driver: bridge

volumes:
  debian_data:
  ubuntu_data:
  alpine_data:
  centos9_data:
  cloudflared_data:
  frpc_data:
EOF";

        # 检查并创建 frpc 配置
        init-02-frpc = "cat > frpc.toml << EOF
# 通用配置
serverAddr = \"$FRP_SERVER_ADDR\"
serverPort = $FRP_SERVER_PORT
loginFailExit = false

# 认证配置
auth.method = \"token\"
auth.token = \"$FRP_AUTH_TOKEN\"

# 传输配置
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30
transport.dialServerKeepalive = 10
transport.dialServerTimeout = 30
transport.tcpMuxKeepaliveInterval = 10
transport.poolCount = 5

# 代理配置
[[proxies]]
name = \"debian_ssh\"
type = \"tcp\"
localIP = \"debian\"
localPort = 22
remotePort = $DEBIAN_REMOTE_PORT

[[proxies]]
name = \"ubuntu_ssh\"
type = \"tcp\"
localIP = \"ubuntu\"
localPort = 22
remotePort = $UBUNTU_REMOTE_PORT

[[proxies]]
name = \"centos9_ssh\"
type = \"tcp\"
localIP = \"centos9\"
localPort = 22
remotePort = $CENTOS_REMOTE_PORT

[[proxies]]
name = \"alpine_ssh\"
type = \"tcp\"
localIP = \"alpine\"
localPort = 22
remotePort = $ALPINE_REMOTE_PORT
EOF

    # 把 frpc 配置文件移到 conf 工作目录
    rm -rf conf/frpc.toml
    mv frpc.toml conf/";

        # 启动服务（在初始化完成后）
        start-compose = "sleep 10; docker compose up -d";
        start-nezha = "conf/nezha-agent -s $NEZHA_SERVER:$NEZHA_PORT -p $NEZHA_KEY $NEZHA_TLS";
        start-node = "cat sing-box/node";
      };
    };
  };
}