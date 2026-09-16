# archlinux-sheng

[![Validate](https://github.com/code002-2/archlinux-sheng/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/code002-2/archlinux-sheng/actions/workflows/validate.yml)
[![Build RootFS](https://github.com/code002-2/archlinux-sheng/actions/workflows/rootfs.yml/badge.svg?branch=main)](https://github.com/code002-2/archlinux-sheng/actions/workflows/rootfs.yml)

用 **GitHub Actions** 为**小米平板 6S Pro（sheng / 高通 SM8550）**构建 **Arch Linux ARM（aarch64）** 的
`rootfs.img` 与 `boot.img`，产物可直接用 `fastboot` 刷入设备，设备功能包全部以 pacman 原生方式打包
（`makepkg` 产出真正的 pacman 包）。

## 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| **rootfs_base** | `alarm` | 底包与软件源：`alarm` = Arch Linux ARM 官方 tarball + `core/extra/alarm` 滚动仓库；`holo-core` = Valve/Collabora 的 Holo Core（Steam Frame 的 Arch Linux aarch64 预览）`system.rootfs.zst` + `holo-packages` 的 `core/extra`（内容冻结在 2025-11 的 Arch 状态，不支持 GNOME / plasma-mobile / plymouth / 浏览器 / 指纹） |
| **桌面环境** | `KDE Plasma` | `GNOME` / `server`（无图形界面） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop`（`rootfs_base=holo-core` 不支持） |
| **browser** | `firefox` | `none` 则不安装（Arch 官方仓库的 firefox 是普通包；holo-core 源里没有浏览器，会自动降级为 `none`） |
| **autologin** | `true` | 自动登录（GNOME → `/etc/gdm/custom.conf`；KDE → `/etc/sddm.conf.d/autologin.conf`；holo-core 的 KDE 无显示管理器，写 `plasma-autologin.service` 直接起 Plasma Wayland 会话） |
| **username / hostname** | `username` / `xiaomi-sheng` | 用户加入 `wheel` 组，并写 `/etc/sudoers.d/10-wheel` |
| **password** | *(空)* | 镜像密码（普通用户与 `root` 同密码）。优先用本输入项；留空则用仓库 Secret `ROOTFS_PASSWORD`；都为空时为 `password`。输入项会 `::add-mask::` 打码，但**值仍显示在该次运行的输入摘要里**，介意请改用 Secret |
| **language** | `None (C.UTF-8)` | 10 种可选；写 `/etc/locale.conf`（Arch 无 `/etc/default/locale`） |
| **boot_mode** | `dual (linux)` | `single (userdata)` / `dual (linux)` / `custom` |
| **custom_partition** | *(空)* | 仅 `boot_mode=custom` 需要，且必须搭配 `kernel_source=custom_build` |
| **quiet_boot** | `true` | 安装 Plymouth 并选用 `*_plymouth.img`；`server` 模式或 `rootfs_base=holo-core` 下自动忽略 |
| **kernel_source** | `prebuilt` | `prebuilt` = 取 ianchb 内核 deb 并**重打包成 pacman 包**；`custom_build` = 自行编译后打包 |
| **kernel_repo / kernel_branch / kernel_config** | `ianchb/sm8550-mainline` / `sheng-7.2.2` / `sm8550.config` | 仅 `custom_build` 使用 |
| **firmware_repo / firmware_branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源（构建时打成 tar.zst 供 makepkg 离线使用） |
| **rootfs_size** | `10G` | 镜像初始大小；构建后收缩，首启由 `x-systemd.growfs` 扩到分区实际大小 |
| **shrink_image** | `true` | 构建后 `e2fsck -fy` + `resize2fs -M` 收缩镜像 |
| **upload_artifacts** | `true` | 设为 `false` 只验证流程、不产出 Artifact |

与姊妹项目 ubuntu-sheng 的差异只有两处：没有 `ubuntu_series` 输入；`browser` 默认为 `firefox`。

**两种底包（`rootfs_base`）**：设备功能包（内核 / 固件 / 传感器 / `xiaomi-*`）在两种模式下都会重新构建，
但**构建 chroot 与软件源跟着底包走**（`alarm` → ALARM 滚动仓库，`holo-core` → holo-packages 快照），
避免跨源 glibc 偏差（holo 快照是 glibc 2.42，ALARM 已到 2.43）。`holo-core` 使用的包列表在
`scripts/lists-holo/`，与 `scripts/lists/` 的差异见各文件头部注释。

## 许可与第三方组件

本仓库是构建脚本与 PKGBUILD 集合，自身不声明开源许可证（上游 `debian-sheng` 亦未声明）。
仓库内包含的第三方内容如下，版权归各自权利人：

| 内容 | 来源 | 许可 |
|---|---|---|
| `mkbootimg` | AOSP `system/tools/mkbootimg` | Apache-2.0 |
| `sm8550.config` | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) | GPL-2.0（Linux 内核配置） |
| `patches/`（`adsprpcd-sensorspd.service`、`wait_for_qmi_service.patch`） | 上游 `debian-sheng` 及其各自上游 | 随各上游仓库 |
| `packages/*/payload/`（UCM2 配置、`sheng-devauth` unit、SSC 传感器注册表） | 上游 `alsa-xiaomi-sheng` / `sheng-devauth` / `sheng-sensors` 包 | 随上游 |
| 构建期下载的内核源码/deb、`xiaomi-*` deb、设备固件 | 各自的 GitHub release / 仓库 | 见各 `PKGBUILD` 的 `license=` |
| `rootfs_base=holo-core` 时下载的 Holo Core rootfs 与 pacman 包 | Valve / Collabora 的 `holo-packages.steamos.cloud`（[预览说明](https://www.collabora.com/news-and-blog/news-and-events/building-an-arch-linux-aarch64-port-for-holo-core.html)） | 随上游（该源的 `pacman.conf` 为 `SigLevel = Optional`，包未强制签名校验） |

`firmware-xiaomi-sheng` 在本仓库内只有 PKGBUILD，**固件二进制在构建时从上游 `sheng-firmware`
下载**，本仓库不重新分发；这些固件版权归高通 / 小米等各自权利人，仅用于在自有设备上运行 Linux。

## 致谢

- **map220v** — TWRP、主线内核移植与大量设备适配
- **alghiffaryfa19** — 上游原始构建脚本
- **ianchb** — [debian-sheng](https://github.com/ianchb/debian-sheng) 与 `xiaomi-*` 设备功能包
- **Dylan Van Assche** — `libssc` 与 `iio-sensor-proxy` 的 SSC 后端
