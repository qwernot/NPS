# Dark's NPS

这是基于 NPS 二次修改的内网穿透服务端/客户端项目。当前版本保留原 NPS 的核心穿透能力，并增加了更适合多人分发使用的管理方式。

## 当前特性

- 管理后台名称改为 `Dark's NPS`
- 管理后台支持管理员创建用户
- 用户支持独立端口池，例如 `5000-6000,7001`
- 普通用户只能在自己的端口池内创建/修改隧道
- 支持 Docker 部署服务端 `nps`
- 支持构建客户端 `npc`

## 镜像

服务端镜像已经推送到 Docker Hub：

```bash
docker pull darkver8/nps:latest
```

## 端口说明

默认配置会使用这些端口：

| 端口 | 用途 |
| --- | --- |
| `8081` | Web 管理后台 |
| `8024` | npc 默认连接端口 |
| `8025` | npc TLS 连接端口 |
| `80` | HTTP 代理 |
| `443` | HTTPS 代理 |
| 用户端口池 | TCP/UDP 隧道端口 |

服务器安全组和防火墙需要放行以上端口，以及你准备分配给用户的端口池范围。

## Docker 部署服务端

推荐把配置文件放在宿主机 `/opt/darks-nps/conf`，容器只负责运行程序。

### 1. 准备配置目录

```bash
mkdir -p /opt/darks-nps/conf
```

如果你是第一次部署，可以从源码里的 `conf` 目录复制一份默认配置：

```bash
cp -r ./conf/* /opt/darks-nps/conf/
```

如果是新机器没有源码，也可以先创建目录，启动前把已有服务器的配置文件复制进去。

### 2. 启动容器

```bash
docker run -d \
  --name nps \
  --restart unless-stopped \
  --network host \
  -v /opt/darks-nps/conf:/conf \
  darkver8/nps:latest
```

使用 `--network host` 是为了让 NPS 直接监听宿主机端口，适合穿透服务这种需要开放大量端口的场景。

### 3. 查看状态

```bash
docker ps --filter name=nps
docker logs --tail=100 nps
```

看到类似下面的日志说明服务已经启动：

```text
web management start, access port is 8081
```

访问后台：

```text
http://服务器IP:8081/login/index
```

默认账号密码来自 `/opt/darks-nps/conf/nps.conf`：

```ini
web_username=admin
web_password=123
```

生产环境请先修改默认密码。

## 更新服务端镜像

```bash
docker pull darkver8/nps:latest
docker rm -f nps
docker run -d \
  --name nps \
  --restart unless-stopped \
  --network host \
  -v /opt/darks-nps/conf:/conf \
  darkver8/nps:latest
```

配置文件挂载在宿主机 `/opt/darks-nps/conf`，删除容器不会删除配置。

## 从源码构建服务端镜像

如果你想自己从源码构建：

```bash
docker build --progress=plain \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f Dockerfile.nps \
  -t darkver8/nps:latest .
```

然后运行：

```bash
docker run -d \
  --name nps \
  --restart unless-stopped \
  --network host \
  -v /opt/darks-nps/conf:/conf \
  darkver8/nps:latest
```

如果网络环境可以直接访问 Go 官方源，也可以不传 `GOPROXY`。

## 构建 npc 客户端

本地安装 Go 后，在源码目录执行：

```bash
go build -o npc ./cmd/npc
```

Windows：

```powershell
go build -o npc.exe ./cmd/npc
```

Linux amd64 交叉编译：

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o npc-linux-amd64 ./cmd/npc
```

也可以构建 Docker 镜像：

```bash
docker build --progress=plain \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f Dockerfile.npc \
  -t darkver8/npc:latest .
```

## npc 连接服务端

在后台创建客户端后，会得到该客户端的 `vkey`。

普通 TCP 连接：

```bash
./npc -server=服务器IP:8024 -vkey=你的vkey
```

TLS 连接：

```bash
./npc -server=服务器IP:8025 -vkey=你的vkey -tls_enable=true
```

Windows 把 `./npc` 换成 `npc.exe`。

## 用户和端口池

管理员登录后台后，进入客户端/用户管理页面新增用户。

新增用户时可以配置：

- Web 用户名
- Web 密码
- 端口池
- 流量限制
- 速率限制
- 最大隧道数
- 最大连接数

端口池格式示例：

```text
5000-6000
5000-6000,7001,7100-7200
```

普通用户登录后台后，只能创建和修改自己名下的隧道；如果配置了端口池，隧道端口必须落在自己的端口池内。

如果同时配置了全局 `allow_ports` 和用户端口池，端口需要同时满足两个限制。

## 常用配置

配置文件位置：

```text
/opt/darks-nps/conf/nps.conf
```

常用项：

```ini
web_username=admin
web_password=123
web_port=8081

bridge_port=8024
tls_enable=true
tls_bridge_port=8025

http_proxy_port=80
https_proxy_port=443

# 全局允许端口，可选
# allow_ports=5000-6000,7001

allow_user_login=true
allow_user_register=false
```

修改配置后重启容器：

```bash
docker restart nps
```

## 备份和迁移

只要备份配置目录即可：

```bash
tar -czf darks-nps-conf.tar.gz -C /opt/darks-nps conf
```

迁移到新服务器：

```bash
mkdir -p /opt/darks-nps
tar -xzf darks-nps-conf.tar.gz -C /opt/darks-nps
docker run -d \
  --name nps \
  --restart unless-stopped \
  --network host \
  -v /opt/darks-nps/conf:/conf \
  darkver8/nps:latest
```

## 常见问题

### 后台打不开

检查容器和端口：

```bash
docker ps --filter name=nps
docker logs --tail=100 nps
ss -ltnp | grep 8081
```

同时确认服务器安全组放行了 `8081`。

### npc 连不上

检查：

- 服务端是否放行 `8024` 或 `8025`
- 后台客户端是否启用
- `vkey` 是否复制正确
- 如果使用 TLS，客户端和服务端端口是否对应

### 隧道端口无法创建

检查：

- 端口是否被系统占用
- 是否在全局 `allow_ports` 内
- 是否在该用户的端口池内
- 服务器安全组是否放行该端口

## 本地开发测试

运行测试：

```bash
go test ./...
```

构建服务端：

```bash
go build -o nps ./cmd/nps
```

构建客户端：

```bash
go build -o npc ./cmd/npc
```
