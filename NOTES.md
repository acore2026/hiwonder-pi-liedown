# TonyPi 机器人开发笔记

> 最后更新：2026-10-14 午后（双机验收通过 + 部署包成军）
> 面向使用者的内容在前（第〇~三章），技术细节与应急手册在后
>
> 🚀 **从零部署 / 换新机器人**：看 [部署手册.md](部署手册.md)（源码在 `src/`，Windows 镜像在 `C:\robot\kit\`，不需要 AI 协助即可完成）
> 🩺 **硬件不动了**：看 `src/diagnostics/README.md` 的诊断阶梯（哔声→IMU→裸串口→重插排座）
> ☁️ **远程仓库**：https://github.com/acore2026/hiwonder-pi-liedown （remote 走 SSH：`git@github.com:acore2026/hiwonder-pi-liedown.git`，本机 `~/.ssh/id_ed25519` 已授权，直接 `git push` 即可）

---

## ⭐⭐ 双机器人体系（2026-10-14 起）

| | 1号（原机） | 2号（备份机） |
|---|---|---|
| IP（RobotLink 网段） | `192.168.137.72` | `192.168.137.172` |
| MAC（wlan0，认机铁证） | `88:a2:9e:00:b2:ec` | `88:a2:9e:00:b3:07` |
| 状态 | 双机验收通过（2026-10-14） | 双机验收通过（2026-10-14）；⚠️ 电池体质弱，用前充满 |
| SSH / HTTP | `ssh pi@192.168.137.72` / `:8090` | `ssh pi@192.168.137.172` / `:8090` |
| 桌面快捷方式 | 已清理（2026-10-28 应用户要求移除）——需要时 `make_shortcuts.ps1` 可随时重建 | 同左 |
| 兜底热点 | HW-9E00B2EB（WPA/hiwonder） | HW-BACKUP2（WPA/hiwonder） |
| WiFi 优先级 | RobotLink 20 > 自家 1 | RobotLink 20 > 自家 1 |
| fall_server 自启 | ✅ systemd（2026-10-14 双机配齐，重启自动回） | ✅ systemd（2026-10-14 配好，重启自动回） |

- 两台可**同时开机**（不同 IP 不冲突）；回调自动带 `robot_ip` 字段可区分是谁
- 回调监视窗口（`机器人-回调监视`）同时显示两台的回调
- ⚠️ IP 是 DHCP：**两台同时重启后 IP 可能互换/漂移**（命令里的 IP 需要更新）
  → 稳妥做法：一次只开一台；或开了之后喊我扫一遍确认 IP
- 2号 时钟已手动校准（2026-10-14），NTP 开着但走不通（VPN 链路），漂移大就再手动校

---

## 〇、手动触发指南（日常使用看这里）

### 前提条件（三个绿灯）

1. ✅ 电脑移动热点 `RobotLink`（密码 hiwonder）开着；电脑 WiFi 连着 `acn-mobile-hotpot`
   保持外网（热点共享它的网络，机器人也借道上网）
2. ✅ 机器人已开机（扩展板蓝灯 LED1 闪烁 + 蜂鸣一声）
3. ✅ 机器人 IP = `192.168.137.72`（DHCP，热点重启后可能变，见下方故障表）

### 方式一：终端命令（可复制粘贴，日常主用）

```powershell
# SSH 版
ssh pi@192.168.137.72 "python3 /home/pi/fall.py"         # 摔倒
ssh pi@192.168.137.72 "python3 /home/pi/stand.py"        # 起立（仰卧）
ssh pi@192.168.137.72 "python3 /home/pi/stand.py front"  # 起立（俯卧）

# HTTP 版（2026-10-13 上线，闭环实测成功）
Invoke-RestMethod http://192.168.137.72:8090/status                                                                        # 查状态
Invoke-RestMethod -Method Post -Uri http://192.168.137.72:8090/fall                                                        # 摔倒（无回调）
Invoke-RestMethod -Method Post -Uri http://192.168.137.72:8090/fall -ContentType "application/json" -Body '{"callback_url":"http://192.168.137.1:9000/robot-callback","request_id":"t1"}'   # 摔倒+回调
Invoke-RestMethod -Method Post -Uri http://192.168.137.72:8090/stand -ContentType "application/json" -Body '{"mode":"front"}'   # 起立（俯卧）
```

**姿态小知识**：摔倒默认仰面（lie_down）→ 起立用默认 back；机器人趴着时起立用 `front`。

⚠️ **PowerShell 大坑**：不要用 `curl.exe -d '{"json"}'` 传 JSON——PS 5.1 会剥掉内层双引号，
服务器收到坏 JSON（表现为 `"callback":false`、request_id 变自动值）。**一律 Invoke-RestMethod**。
（Linux/WSL2 里真 curl 无此问题。）

### HTTP 服务详情（已部署，双机闭环实测通过）

| 组件 | 位置 | 状态 |
|---|---|---|
| 机器人端服务 | `/home/pi/fall_server.py`（Flask :8090） | **systemd 常驻**（`fall-server.service`），开机自启+崩溃自动重启，**无需手动管** |
| 本机回调接收器 | `C:\robot\cb_listener.py`（:9000） | 后台运行中，**电脑重启后需手动重启**（见下；可配计划任务自启） |
| 防火墙 | 规则 `robot-callback-9000`（TCP 9000 入站） | 已配置 |

机器人端异常时查/重启：`ssh pi@<机器人IP> "systemctl status fall-server"` / `sudo systemctl restart fall-server`
重启本机监听器：`powershell -File C:\robot\kit\windows\install_listener.ps1`
看回调日志：`Get-Content C:\robot\listener.log -Tail 10 -Wait`
API/回调格式：[HTTP触发方案.md](HTTP触发方案.md)

### 可用动作组（共 118 个，常用如下）

`lie_down`（躺下·摔倒默认）、`bow`（鞠躬）、`sit_ups`（仰卧起坐）、`stand`（站立复位）、
`stand_up_back` / `stand_up_front`（起立）、`stand_slow`（慢速站立）

查看全部：`ssh pi@192.168.137.72 "ls /home/pi/TonyPi/ActionGroups/"`
HTTP 触发任意动作：`POST /fall` 带 `{"action":"bow"}`

### WonderPi App 控制

机器人自身热点已停用 → App 里用**局域网模式**，填 IP `192.168.137.72`。

### 故障 30 秒自检表

| 症状 | 大概率原因 | 办法 |
|---|---|---|
| SSH/HTTP 都超时 | RobotLink 热点没开 / 机器人没开机 / IP 变了 | 电脑设置里开热点；查机器人电源；IP 变了喊我扫（banner 验证法） |
| 电脑重启后全断 | 热点和监听器都没了 | 开热点（脚本 `bin/hotspot.ps1`）→ 重启监听器（上方命令） |
| SSH 通但 HTTP 不通 | fall_server 没起（机器人重启过） | 见上方"HTTP 服务详情"重启命令 |
| HTTP 通但收不到回调 | 监听器没跑 / 防火墙 | 重启监听器；查规则 `robot-callback-9000` |
| WSL2 里连不上机器人 | **WSL2 → 热点子网路由被 VPN TUN 干扰**（实录） | 一律走 Windows 侧（powershell ssh / Invoke-RestMethod） |
| 摔倒后起立失败 | 姿态不匹配 | 换 `front`，或 `reset` |
| Host key 警告 | 机器人 IP 变化后首次连接 | `ssh-keygen -R <旧IP>` 再连，或喊我处理 |

---

## 一、当前架构（2026-10-13 下午起：RobotLink 直连）

```
Internet(蜂窝) ── acn-mobile-hotpot ──┐
                                      │ WiFi客户端
                              电脑(双角色) ── WSL2 (NAT)
                                      │ Windows移动热点 "RobotLink"(2.4GHz, ICS共享)
                              机器人(192.168.137.72) ── HTTP :8090 / SSH :22
```

- **电脑双角色**：WiFi 客户端连 acn 保持外网 + 移动热点 RobotLink 供机器人接入（ICS 共享外网）
- **SSH 直连**：`ssh pi@192.168.137.72`（Windows 侧通；**WSL2 侧路由被 VPN 干扰不通**，走 Windows）
- **HTTP 服务**：fall_server.py :8090（闭环已验证：触发→摔倒→回调）
- **热点网关** = 电脑 = `192.168.137.1`（回调目标地址）
- **单射频限制**：机器人连 RobotLink 后不再广播自己的热点
- **IP 是 DHCP**：热点/电脑重启可能换 IP

### 架构坑实录（2026-10-13）

1. **5GHz 高段信道不兼容**（acn 时代教训）：机器人 WiFi 模组不支持 ch149+；
   RobotLink 跟随电脑 WiFi 客户端频段（2.4GHz）→ 兼容 ✓
2. **nmcli con down 阻断自愈**：手动 down 的连接不再自动重连 → 断电重启恢复
3. **幽灵 TCP 应答**：安卓热点对任意 IP:Port "接受连接但不传数据" → 扫描必须验 banner
4. **hotspot7.ps1 的 ConfigureAccessPointAsync 会把开着的热点弄关** → 重配后必须再跑
   hotspot.ps1 的 StartTetheringAsync；hotspot.ps1 的读配置段报错但 Start 部分正常
5. **`\\wsl.localhost` 共享偶尔卡死**：`powershell -File \\wsl\...` 会挂起零输出 →
   先拷到 `C:\Users\Public\` 再执行
6. **WSL2 → 192.168.137.x 路由不通**（Windows 侧正常）：疑 Meta/mihomo VPN TUN 抢路由；
   所有机器人操作走 Windows 侧

### 机器人 WiFi 切换命令（在机器人上执行）

```sh
# 连电脑热点 RobotLink（当前生效）
sudo nmcli con add type wifi con-name rob ifname wlan0 ssid RobotLink   # 已建
sudo nmcli con modify rob wifi-sec.key-mgmt wpa-psk wifi-sec.psk "hiwonder"
sudo nmcli con modify rob connection.autoconnect yes
sudo nmcli con up rob

# 连 acn 手机热点（备用）
sudo nmcli con up acn    # acn 连接已存在：acn-mobile-hotpot / td1234567

# 回机器人自身热点（桥接方案）
sudo nmcli con up HW-9E00B2EB
```

---

## 二、机器人档案

- **型号**：TonyPi 人形机器人（HiWonder），18 舵机，圆口适配器供电
- **主机**：树莓派，Debian 12 bookworm，hostname=raspberrypi，默认 shell=zsh（echo `=xxx` 会被展开）
- **SSH/VNC 账号**：`pi` / `raspberrypi`（公钥免密已部署；pi 免密 sudo ✓）
- **USB-C 对 PC 无数据功能**（两次验证）→ 所有通信必须走 WiFi
- **开机标志**：扩展板蓝灯 LED1 闪烁 + 蜂鸣一声；AP↔LAN 切换 = 长按 KEY1 键 5-10 秒
- **官方服务**：RPCServer.py（:9030）、TonyPi.py（MJPEG :8080）等开机自启（占 9026/9030/8080）
- Python 库：flask 2.2.2、requests 2.31.0；SDK 在 `/usr/local/lib/python3.11/dist-packages/hiwonder/`
- **SDK 关键模式**：动作前必须 `rrc.Board()` + `board.enable_reception()`（fall.py/官方例程同款）

### 动作组 = SQLite（.d6a）

- 位置：`/home/pi/TonyPi/ActionGroups/`（118 个）
- 表结构：`ActionGroup([Index] PK, Time INT, Servo1..Servo18 INT)`，500=中位，0-1000
- 官方例程：`Fall_and_Stand.py`（IMU 倾倒检测 + runActionGroup）
- API：`AGC.runActionGroup('名字')`；`board.get_imu()`；速度修改 = Time 列乘系数

### 安全包络（重要）

- **4 秒 lie_down = 原厂速度 = 安全上限**（再快有冲击/齿轮风险，拒绝 ×<1）
- ×2（8 秒）/ ×4（16 秒）慢放同一轨迹，安全
- 摔倒/起立实验必须在地板 + 周围留空（用户已确认环境）

---

## 三、机器人上部署的脚本（二次开发）

| 脚本 | 用法 | 说明 |
|---|---|---|
| `/home/pi/fall.py` | `python3 fall.py [动作名]` | 纯摔倒，默认 lie_down，完成后躺平保持 |
| `/home/pi/stand.py` | `python3 stand.py [back\|front\|reset]` | 纯起立，默认 back（仰卧爬起） |
| `/home/pi/fall_demo.py` | `python3 fall_demo.py [动作名]` | 三合一演示：站立→摔倒→爬起 |
| `/home/pi/fall_server.py` ⭐ | HTTP 服务 :8090 | 见第〇章"HTTP 服务详情"+ [HTTP触发方案.md](HTTP触发方案.md) |

输出标志行：`FALL: ... fall done.` / `STAND UP: ... stand done.`（便于远程解析）

**旧机器人遗留**（新机未部署，需要可重写）：`make_fall.py`（动作速度生成器）、
`slow_fall.d6a`（×4 慢摔 16 秒）——思路：复制 lie_down.d6a，Time 列 ×N（clamp 20-9900）

---

## 四、运维手册

### 机器人开机联网逻辑（2026-10-23 起 1号 加 dev 看门狗）

开机 → NetworkManager 扫描 → 按**优先级**依次尝试（全部 autoconnect=yes）：

| 优先级 | 连接 | 说明 |
|---|---|---|
| **30** | `dev`（仅 1号） | **另一台电脑的热点**（5GHz ch44，密码 huawei123）——可见就连它 |
| 20 | `RobotLink` | 电脑热点，dev 不在时的首选 |
| 10 / 5 | `acn` / `acn-mobile-hotpot` | acn 手机热点（两个重复配置，无害） |
| 1 | `HW-9E00B2EB` | 都连不上时自己广播热点兜底（WPA/hiwonder，共享模式 10.42.0.1）→ 手机连它可走第六章桥接应急 |

**⚠️ NetworkManager 的坑**：优先级只在"选网"时生效（开机/断线重连）——**连着 RobotLink 时即使 dev 出现也不会自动跳槽**。
→ 1号 已部署 **dev-watchdog** systemd 服务（`src/dev_watchdog.sh` + `deploy/dev-watchdog.service`）：
每 60 秒巡检，"不在 dev 且 dev 可见"就切换。**这才是真正的"永久优先 dev"**（2026-10-23 实测：80 秒内自动跳槽）。
2号 尚未配 dev——开机后照抄：`nmcli` 加 dev 配置（优先级 30）+ 装 dev-watchdog 服务。

依赖链：机器人有网 ⟸ dev 或 RobotLink 至少一个在广播。
调优先级命令：`sudo nmcli con modify <名字> connection.autoconnect-priority <数字>`

### 机器人重启后（约 1~2 分钟回网）

1. 等蓝灯闪 + 蜂鸣"哔"；机器人自动连 RobotLink（优先级 20）
2. **前提：电脑的 RobotLink 热点开着**（电脑重启后热点默认关闭 → 先开热点）
3. **fall_server 由 systemd 自动拉起**，无需任何手动操作
4. IP 通常不变（.72/.172）；两台同时重启可能互换 → `scan_robots.ps1` 扫
5. ⚠️ 机器人无硬件时钟：崩溃式断电后时间会倒退（软件功能不受影响，
   回调时间戳会错 → 跑一遍 `fix_robot.ps1` 校准）

### 电脑重启后

1. 开热点：`powershell -File C:\robot\kit\windows\hotspot_on.ps1`
   （电脑 WiFi 先连回 acn-mobile-hotspot 保持外网）
2. 重启监听器：`powershell -File C:\robot\kit\windows\install_listener.ps1`
3. 机器人自动重连热点；IP 若变则 `scan_robots.ps1` 扫

### 换机器人流程（2026-10-14 版，约 10 分钟）

> **完整手册看 [部署手册.md](部署手册.md)**（源码 `src/`，Windows 镜像 `C:\robot\kit\`），下面是速览。
> 新机 = 出厂状态：不认识 RobotLink，只广播自己的热点 HW-XXXX（密码 hiwonder）。

```powershell
# 1. 手机/电脑连机器人的 HW-XXXX 热点 → ssh pi@10.42.0.1（密码 raspberrypi）
#    配它连 RobotLink:
#    sudo nmcli dev wifi connect RobotLink password hiwonder ifname wlan0
# 2. 种公钥（手输一次密码 raspberrypi）：
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh pi@<新IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
# 3. 一键部署（脚本+systemd）：
powershell -File C:\robot\kit\windows\deploy_robot.ps1 -RobotIP <新IP>
# 4. 调优（WiFi优先级+兜底热点+时钟，兜底热点名每台起不同名）：
powershell -File C:\robot\kit\windows\fix_robot.ps1 -RobotIP <新IP> -ApName HW-新机名
# 5. 快捷方式 + 验收：
powershell -File C:\robot\kit\windows\make_shortcuts.ps1 -RobotIP <新IP> -Prefix 机器人N
powershell -File C:\robot\kit\windows\test_robot.ps1 -RobotIP <新IP>
```

### IP 变了怎么找

`powershell -File C:\robot\kit\windows\scan_robots.ps1`（banner 验证扫描，
WSL2 路由不通必须从 Windows 侧跑）→ 找到新 IP 后重跑 make_shortcuts.ps1

### 桥接方案回退（直连失效时的应急）

前提：恢复机器人自身热点（重启或 KEY1 长按）→ 见第六章完整手册

---

## 五、踩坑速查表（按症状）

| 症状 | 根因 | 解法 |
|---|---|---|
| **软件全成功但机器人零动作** | 扩展板 MCU 挂死 或 串口断连——用诊断阶梯区分（`src/diagnostics/README.md`） | 见下两行；完整阶梯：哔声→IMU→裸串口 |
| MCU 挂死（无哔 或 哔了但 IMU=None 且裸串口有数据） | 电池电压跌落致芯片闩锁 | **整机断电 15 秒重启**（2026-10-14 双次实测有效）；树莓派软重启救不了 MCU |
| **开机有哔 + IMU=None + 裸串口静默**（2026-10-14 实锤） | **树莓派与扩展板之间 40 针排座松动**（供电针接触好但串口针悬空：能开机、能哔、不通信） | 断电 → 把树莓派从扩展板拔起 → 对准重插到底 → 上电（实测一次根治，扛过重启） |
| **验收标准（重要）** | 回调 ok=True 只证明脚本跑完，不证明物理动作 | **IMU 前后对比才是铁证**：站立重力在X轴(-0.96,-0.03)，躺平转Z轴(-0.04,-1.04)；终极验收靠肉眼 |
| ssh 超时/拒绝 | IP 变 / 设备离线 / 热点没开 | `scan_robots.ps1` 扫 |
| 全网段端口"开放" | 安卓热点幽灵 TCP 应答 | 扫描必须验 banner |
| 机器人连不上 5GHz 热点 | WiFi 模组不支持高段信道(149+) | 热点改 2.4GHz |
| 机器人时间倒退一天 | 无硬件时钟 + 崩溃式断电（fake-hwclock 回退） | `fix_robot.ps1` 校准；NTP 走不通（VPN 挡 UDP） |
| `get_battery()` 返回 None | 本板固件不支持电压查询（健康机器人也 None） | 别用它判断电池——看症状（动作后崩溃≈电池虚） |
| 2号 电池体质弱（2026-10-14 判定） | 备份机长期存放自放电：真动作后连环崩 | 用前充满电；反复 MCU 挂死先怀疑电池 |
| 机器人网络孤岛 | con down 阻断自愈 | 断电重启 |
| nmcli 报 Insufficient privileges | 非交互 SSH 无权 | 加 sudo |
| **远程命令静默自杀（零输出）** | `pkill -f xxx` 匹配到执行命令的 shell 自己 | 模式写成 `pkill -f 'fal[l]_server'` 括号正则，或分两步执行 |
| **curl.exe 传 JSON 服务端收不到** | PS 5.1 剥掉内层双引号 | 用 Invoke-RestMethod |
| **powershell -File \\wsl\... 挂起** | \\wsl.localhost 共享卡死 | 脚本先拷到 C:\ 再跑 |
| **WSL2 连不上热点子网** | VPN TUN 抢路由 | 走 Windows 侧 |
| （桥接）中继 bind: Address already in use | toybox nc 注册名是 netcat | kill_relay_v2.sh 按 pid 击杀 |
| （桥接）偶发 Connection closed | 中继循环空窗 | sleep 0.2 |
| （桥接）PowerShell 引号被吞 | 内联 shell 转义 | 永远推送 .sh 文件执行 |

---

## 六、历史架构：手机桥接（已退役·应急手册）

> 2026-10-12 全程实战验证；直连方案的兜底，机器人自身热点可用时才能启用

```
WSL2 ──→ portproxy 172.18.96.1:2222 ──→ adb forward 127.0.0.1:2222
      ──→ USB ADB ──→ 手机 nc中继 :8022 ──→ WiFi(机器人热点) ──→ 机器人:22
```

### 三大关键组件

1. **持久 adb server**（Windows）：`Start-Process adb start-server`（输出重定向）。
   坑：Start-Job 的 Job Object kill-on-close 会杀 job 派生的 adb server → forward 丢失
2. **手机 nc 中继 v4**（`/data/local/tmp/relay.sh`，setsid 运行）：
   ```sh
   while true; do
     nc -l -p 8022 nc -w 5 "$ROBOT" 22   # COMMAND模式：来客户端才连机器人，5s 超时
     sleep 0.2
   done
   ```
3. **portproxy**（已配好，持久）：`netsh interface portproxy add v4tov4
   listenaddress=172.18.96.1 listenport=2222 connectaddress=127.0.0.1 connectport=2222`

### 机器人热点两套配置（IP 会互换，先测再连）

- `10.42.0.1`：NetworkManager 共享模式（热点开放）
- `192.168.149.1`：HiWonder 标准模式（WPA/hiwonder）
- 判断：手机 `ip -4 addr show wlan0` 看网段，网关即机器人

### 桥接恢复流程

1. 手机连机器人热点：`adb shell cmd wifi connect-network HW-9E00B2EB wpa2 hiwonder`
2. 改 relay.sh 的 `ROBOT=<IP>` → push → `kill_relay_v2.sh` 清旧 → setsid 重启
3. `adb forward tcp:2222 tcp:8022`（adb server 重启会丢，必查）
4. 一条龙脚本：`bin/reboot_recovery.ps1`；完整诊断：`bin/diag_net.ps1`

### 换机器人适配（历史记录：2026-10-12 实测 5 分钟）

> ⚠️ 当前完整流程已更新至第四章"换机器人流程"（含 fall_server 与 WiFi 配置部署），
> 本节仅保留当时桥接时代的实录。

新机差异：SSID 变（MAC 生成）、IP 可能翻面、主机密钥变、出厂无我们脚本。
步骤：扫新 SSID → 改 relay 目标 → `ssh-keygen -R "[172.18.96.1]:2222"` →
sshpass 首登（pi/raspberrypi）→ 部署公钥 + fall/stand/fall_demo 脚本

---

## 七、凭据汇总

| 项目 | 值 |
|---|---|
| 电脑热点（当前） | `RobotLink` / `hiwonder`（Windows 移动热点，2.4GHz） |
| **另一台电脑热点** | `dev` / `huawei123`（5GHz 信道 44；1号 已配置，优先级 30 高于 RobotLink——dev 在覆盖范围内时机器人优先连它） |
| 电脑外网 WiFi | `acn-mobile-hotpot` / `td1234567`（2.4GHz 蜂窝） |
| 机器人 IP | 1号 `192.168.137.72` / 2号 `192.168.137.172`（DHCP，可能漂移；**连 dev 时 IP 由那台电脑重新分配**） |
| 电脑热点网关 IP | `192.168.137.1`（= 回调目标地址） |
| 机器人 SSH/VNC | `pi` / `raspberrypi`（两台相同） |
| 机器人兜底热点 | 1号 `HW-9E00B2EB` / 2号 `HW-BACKUP2`，密码均 `hiwonder` |
| SSH 密钥 | WSL2 `~/.ssh/id_ed25519` + Windows `%USERPROFILE%\.ssh\`，两台均已部署 |
| 手机（桥接备用） | Xiaomi 12S Pro（序列号略），adb 在 `C:\Users\Public\platform-tools\` |
| HTTP 服务端口 | 机器人 :8090（fall_server）；本机 :9000（cb_listener） |
| 部署包 | WSL `~/hiwonder/src/` ＝ Windows 镜像 `C:\robot\kit\`（改代码改一处，cp 镜像另一处） |
| 远程代码 | GitHub `DylanMing/hiwonder-pi-liedown` ＋ ACN 服务器 `/root/zqm/hiwonder-tonypi`（git pull 更新） |

## 八、待办 / 展望

- [x] **HTTP 触发方案：已上线并闭环实测**（2026-10-13）→ [HTTP触发方案.md](HTTP触发方案.md)
- [x] **双机器人体系上线**（2026-10-14）：2号 全套部署 + 双机同网验收（摔倒+回调 ×2）
- [x] fall_server systemd 自启（2026-10-14 **双机配齐**，deploy_robot.ps1 一键搞定）
- [x] **自足部署包**（2026-10-14）：[部署手册.md](部署手册.md) + `src/` + Windows 镜像 `C:\robot\kit\`
- [x] 硬件诊断方法论（哔声→IMU→裸串口阶梯，含 40 针排座重插术）→ `src/diagnostics/`
- [ ] 本机监听器开机自启（任务计划程序，手册第六章有现成命令）
- [ ] 机器人静态 IP 或 mDNS（免 IP 漂移）
- [ ] 公网回调测试（阶段 3，需回调目标 URL）
- [ ] slow_fall 慢摔动作移植（make_fall.py 重写，5 分钟）
- [ ] IMU 触发的受控摔倒 / 动作编排 / 外网直触发（Tailscale）
- [ ] 2号 电池保养提醒：用前充满（体质弱，动作后崩过）
