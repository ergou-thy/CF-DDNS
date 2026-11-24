# CF-DDNS · Cloudflare 动态域名一键部署

> 桃花源出品 · Telegram：[@taohuayuang](https://t.me/taohuayuang)

一个自包含的 Cloudflare DDNS 脚本：装好后自动跟随本机公网 IP 变化，更新 Cloudflare DNS 记录。

- 单文件部署，菜单内嵌，不需要额外文件
- 支持中文域名（自动转 punycode）
- 小黄云 / 灰云切换，TTL 自动同步
- systemd timer 或 crontab 定时，自动去重
- 独立的换 IP 记录日志
- 批量部署多台机器
- 自带管理菜单：状态 / 日志 / 立即执行 / 改配置 / 连通测试 / 卸载

---

## 一键安装

在 Linux 服务器上执行（root）：

```bash
curl -fsSL https://raw.githubusercontent.com/ergou-thy/CF-DDNS/main/ddns.sh -o ddns.sh && bash ddns.sh
```

如果 GitHub 直连慢，用镜像：

```bash
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/ergou-thy/CF-DDNS/main/ddns.sh -o ddns.sh && bash ddns.sh
```

脚本会依次询问：

1. **Cloudflare API Token**（权限 `Zone → DNS → Edit`）
2. **节点域名**（中文或 punycode 都行，比如 `jp1.example.com`）
3. **代理模式**：小黄云（隐藏源站）或灰云（仅 DNS）
4. **检测间隔**：默认 300 秒

装完会：

- 写入配置 `/opt/cf-ddns/cf-ddns.conf`（权限 600）
- 生成运行脚本 `/opt/cf-ddns/cf-ddns-run.sh`
- 生成管理菜单 `/opt/cf-ddns/ddns-menu.sh`
- 创建快捷命令 `ddns`
- 配置 systemd timer（或 crontab）
- 立即执行一次，把当前 IP 写进 Cloudflare

---

## 日常使用

```bash
ddns
```

打开管理菜单：

```
1  运行状态      5  定时任务
2  日志记录      6  连通测试
3  立即执行      7  批量部署
4  修改配置      8  卸载程序
0  退出管理      9  关于作者
```

### 修改配置

菜单 4 可以改：

- 节点域名（自动匹配 Zone）
- 检测间隔
- 小黄云 / 灰云
- API Token
- DNS TTL

改动会立即同步到 Cloudflare。

### 日志

| 文件 | 内容 |
|---|---|
| `/var/log/cf-ddns.log` | 运行日志 |
| `/opt/cf-ddns/ip-change.log` | 换 IP 记录 |

### 卸载

菜单 8，输入 `yes` 确认。不会删除 Cloudflare 上的 DNS 记录。

---

## 环境要求

- Linux（Debian / Ubuntu / CentOS 等）
- `bash`、`curl`、`python3`
- systemd 或 crontab（二选一，有 systemd 优先用 timer）

---

## Cloudflare Token

1. Cloudflare → My Profile → API Tokens → Create Token
2. 模板选 **Edit zone DNS**，权限 `Zone → DNS → Edit`
3. Zone Resources 选你的域名
4. 复制 Token，安装时粘贴

---

## 常见问题

**Q：小黄云下为什么 TTL 改不了？**
代理模式（小黄云）下 Cloudflare 会把 TTL 固定为 300 秒，灰云才生效。

**Q：提示“获取 IP 失败”？**
脚本会依次尝试 AWS 元数据、ipify、ifconfig.me 等接口，全部失败通常是服务器网络/DNS 问题。

**Q：定时任务没跑？**
`systemctl status cf-ddns.timer` 或 `crontab -l` 看一眼；脚本会自动清理重复的 cron。

**Q：能用在多台机器吗？**
可以，菜单 7 支持批量写入配置；每台机器再执行一次 `bash ddns.sh` 补装运行环境。

---

## 声明

仅供个人学习与自用，请遵守 Cloudflare 服务条款。

## License

MIT
