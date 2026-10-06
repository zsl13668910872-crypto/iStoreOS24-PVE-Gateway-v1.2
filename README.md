# iStoreOS 24.10 PVE 旁路由固件（OpenClash 内核内置版）v1.2

> v1.2：修 dnsmasq/dnsmasq-full 双装冲突（rootfs file clashes Error 255），落账检查加正反向断言
> v1.1：files/ 覆盖层按「VUM 一键部署版 iStoreOS24」现网可用配置逐项复刻
> （接口结构、dnsmasq 转发、防火墙区域/FullCone/转发关系），见下节。

基于 iStoreOS 官方源码（istoreos/istoreos，分支 `istoreos-24.10`）编译的
x86_64 PVE 旁路由固件，OpenClash + mihomo 内核（linux-amd64-v3）+ GEO 数据库
全部在编译期打进固件，**首次开机即用，无需任何联网下载**。

## 与 ImmortalWrt v5.2 项目的差异

| 项 | 本项目 | 说明 |
|---|---|---|
| 底包 | iStoreOS 24.10 | 自带 istore 商店、NAS 向组件 |
| 代理插件 | 仅 OpenClash | 不含 dae/daed/nikki |
| 内核 BTF | 不需要 | 去掉 LLVM/pahole 链，编译更快 |
| mihomo 内核 | **编译期内置** `files/etc/openclash/core/clash_meta` | workflow「烘焙」步骤从 MetaCubeX 官方 release 下载 amd64-v3 版并在 runner 上实测 `-v` 通过才继续 |
| GEO 数据库 | 内置 GeoIP.dat / GeoSite.dat / Country.mmdb | MetaCubeX meta-rules-dat 官方最新版 |
| Docker | 默认关闭 | 旁路由不需要，省 20~30 分钟编译；需要时删 config 里 5 行注释即可 |
| IPv6 | 保留内核支持 + 复刻 VUM 版双接口 | lan 自带 fd00::78/64；IPV6 为 DHCPv6 客户端，从主路由取公网 v6 |

## 继承自 v5.2 的排雷经验（已内置）

1. `# CONFIG_RUBY_ENABLE_YJIT is not set` —— 防 rust 源码编译炸掉（2 小时白跑）；
2. 只留 `libustream-openssl` 单变体 —— 防 rootfs 打包 file clashes Error 255；
3. 落账检查含正向（8 项必须 =y）+ 反向（mbedtls/YJIT 必须未选）；
4. 前置自检、绝对路径、失败自动诊断（含 opkg Collected errors 关键词）、
   build.log 永远上传、Release 权限 contents: write 已声明。

## 网络预置（files/ 覆盖层，开机生效）——v1.1 复刻 VUM 版

接口（与 VUM 版接口页一致：无 wan/wan6，只有 lan + IPV6）：

- lan：br-lan(eth0)，静态 `10.10.10.78/24`，广播 10.10.10.255，
  网关 `10.10.10.1`，自带 ULA `fd00::78/64`；
  自身上网 DNS `223.5.5.5` / `119.29.29.29`（peerdns 关）；
- IPV6：DHCPv6 客户端（br-lan），从 RouterOS 主路由获取公网 v6 地址，
  reqprefix=no（旁路由不要前缀委派）；
- lan 口 DHCP 服务器：关闭（ignore=1，ra/dhcpv6 disabled），由主路由分配。

dnsmasq（复刻 VUM 版「转发 127.0.0.1#1053」架构，本固件对应 OpenClash）：

- DNS 重定向关闭；唯一授权开；本地域 /lan/、扩展 HOSTS 开；
- noresolv + 唯一转发 `127.0.0.1#7874`（OpenClash DNS 端口），即
  客户端 → dnsmasq:53 → OpenClash:7874，Fake-IP 在 7874 应答。

防火墙（复刻 VUM 版区域页）：

- 常规：输入拒绝 / 出站接受 / 转发拒绝、SYN-flood 开、丢弃无效包关、
  **FullCone-NAT 高性能模式**（iStoreOS 24.10 中 defaults.fullcone=2，
  已核对 jjm2473/luci 源码取值映射）；
- 区域：lan（含 lan+IPV6）全接受 → 转发到 wan、docker；
  wan 全接受 + IP 动态伪装 + mtu_fix（无实体接口，悬空引用与 VUM 版一致）；
  docker 全接受 → 转发到 wan、lan（本固件未编 Docker，区域保留无影响）；
- 额外保留 OpenClash 专用 `tun` 区域（utun/tun+）+ lan→tun 转发，
  以及 DNS/7891/9090 放行规则——Fake-IP 增强 / TUN 混合两种模式都兼容。

其余：

- OpenClash：UCI 预置 Meta 内核模式，cn_port 7891，控制器 9090；
- sysctl：ip_forward=1、conntrack 26 万、TCP FastOpen、缓冲区调优；
- 删除了 v1.0 的 uci-defaults 收尾脚本（它在做 IPv4-only 时代的 v6 清理，
  与复刻目标冲突）；
- 不含 BBR：旁路由单臂转发场景收益极小，且只有 sysctl 控制面无 LuCI 开关，
  本次直接不编译（需要时可自行加回 CONFIG_PACKAGE_kmod-tcp-bbr=y）。

## 使用流程

1. 本 zip 解压，把**文件夹内容**（含 .github）推送到 GitHub 仓库根目录；
2. Actions → Run workflow（可选填 mihomo 版本号，默认 v1.19.13）；
3. 约 1~1.5 小时后从 Artifacts 下载固件（或勾 publish_release 自动发 Release）；
4. PVE 导入：`gunzip` → `qm importdisk <VMID> <img> local-lvm` → 挂载 scsi0
   → OVMF(q35) 或 SeaBIOS 均可引导；
5. 开机后 `http://10.10.10.78` 进 LuCI → 服务 → OpenClash，直接导入你的
   v6_23 系列配置文件即可（内核已就位，界面会显示内核版本号）。

## 验证清单（编译成功标准）

- Artifacts 里出现 `istoreos-24.10.*-x86-64-generic-squashfs-combined-efi.img.gz`；
- 装机后 OpenClash 版本更新页显示内核 v1.19.x（无需点一键更新）；
- `nslookup www.google.com 10.10.10.78` 返回 `198.18.x.x`（Fake-IP 生效）。
