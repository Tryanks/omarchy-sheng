# archlinux-sheng

[![Validate](https://github.com/code002-2/archlinux-sheng/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/code002-2/archlinux-sheng/actions/workflows/validate.yml)
[![Build RootFS](https://github.com/code002-2/archlinux-sheng/actions/workflows/rootfs.yml/badge.svg?branch=main)](https://github.com/code002-2/archlinux-sheng/actions/workflows/rootfs.yml)

用 **GitHub Actions** 为**小米平板 6S Pro（sheng / 高通 SM8550）**构建 **Arch Linux ARM（aarch64）** 的
`rootfs.img` 与 `boot.img`，产出物可直接用 `fastboot` 刷入设备。
构建逻辑移植自 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng)（Debian 版），
但**设备功能包全部改以 pacman 原生方式打包**：在宿主机上准备一个可复用的 ALARM aarch64 chroot，
用 `makepkg` 产出真正的 pacman 包（可 `pacman -Q/-R`、参与依赖解析），
而不是把 Debian 的 `.deb` 直接铺进文件系统。

## 已验证的构建

以下配置已在本仓库的 GitHub Actions 上**实际跑通并产出镜像**（2026-09-11）：

| 配置 | 构建记录 | 产物 | Artifact 大小¹ | 整轮耗时 |
|---|---|---|---|---|
| Arch / **server** | [run 34602349002](https://github.com/code002-2/archlinux-sheng/actions/runs/34602349002) | `rootfs-arch-server-linux`<br>`boot-arch-server-linux` | 2304.8 MB<br>15.7 MB | ≈10 分钟 |
| Arch / **KDE Plasma** | [run 34603386520](https://github.com/code002-2/archlinux-sheng/actions/runs/34603386520) | `rootfs-arch-KDE-Plasma-linux`<br>`boot-arch-KDE-Plasma-linux` | 4163.2 MB<br>15.7 MB | ≈10 分钟 |

¹ Artifact 是 zip 压缩后的大小；`rootfs.img` 是 ext4 镜像，刷写前以解压后的实际大小为准（构建日志与 step summary 会打印）。

同一次运行还会上传 10 个设备功能包的 pacman 包（`kernel-prebuilt-pkg`、`firmware-xiaomi-sheng-pkg`、
`libssc-pkg`、`iio-sensor-proxy-pkg`、`fastrpc-pkg`、`sheng-sensors-pkg`、`sheng-devauth-pkg`、
`alsa-xiaomi-sheng-pkg`、`xiaomi-pkgs` 等），便于单独取用或排查。

> 因为宿主机 runner 本身就是 arm64，整个流程**不需要 qemu/binfmt**；
> 又因为 pacman 用并行下载，Arch 侧比 Ubuntu 侧快得多（同样的桌面安装步骤约 1 分钟）。

**镜像尚未在真机上刷写验证过。**

## 快速开始

1. **Fork 本仓库**（公开仓库可用免费的 `ubuntu-24.04-arm` 原生 arm64 runner）。
2. **设置密码**：Settings → Secrets and variables → Actions → New repository secret，名称 `ROOTFS_PASSWORD`。
   > 未设置时构建仍会成功，但镜像里普通用户与 `root` 的密码会是默认值 `password`，构建日志会给出 `::warning::`。
3. **运行构建**：Actions → **Build RootFS (Arch Linux ARM)** → Run workflow（保持默认参数即可）。
4. **下载产物**：该次运行的 Summary 页 → Artifacts → `rootfs-*.zip` 与 `boot-*.zip`。
5. **刷写**（假设使用 B 槽与 `linux` 分区）：

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

6. **首启检查**：`df -h /`（growfs 生效）、`uname -r`（与 `/usr/lib/modules/` 一致）、
   `dmesg | grep -i -E 'firmware|adreno|ath12k'`、`systemctl status adsprpcd-sensorspd iio-sensor-proxy`、
   能自动进桌面、`nmcli` 看到 WCN7850、`pacman -Q iio-sensor-proxy-sheng` 有输出，
   并实测 6 个 `xiaomi-*` 功能（快充 / 关机充电 / 触控与手写笔 / 手写笔状态 / 指纹 / 键盘麦克风指示灯）。

## 参数说明

输入项与姊妹项目 [ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng) 一一对应，只有两处差异
（`ubuntu_series` 不存在；`browser` 默认 `firefox`，因为 Arch 官方仓库的 firefox 就是普通包）。

| 参数 | 默认值 | 说明 |
|---|---|---|
| **桌面环境** | `KDE Plasma` | `GNOME` / `server`（无图形界面） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop` |
| **browser** | `firefox` | `none` 则不安装 |
| **autologin** | `true` | 自动登录（GNOME → `/etc/gdm/custom.conf`；KDE → `/etc/sddm.conf.d/autologin.conf`） |
| **username / hostname** | `username` / `xiaomi-sheng` | 用户加入 `wheel` 组，并写 `/etc/sudoers.d/10-wheel` |
| **language** | `None (C.UTF-8)` | 10 种可选；写 `/etc/locale.conf`（Arch 无 `/etc/default/locale`） |
| **boot_mode** | `dual (linux)` | `single (userdata)` / `dual (linux)` / `custom` |
| **custom_partition** | *(空)* | 仅 `boot_mode=custom` 需要，且必须搭配 `kernel_source=custom_build` |
| **quiet_boot** | `true` | 安装 Plymouth 并选用 `*_plymouth.img`；`server` 模式下自动忽略 |
| **kernel_source** | `prebuilt` | `prebuilt` = 取 ianchb 内核 deb 并**重打包成 pacman 包**；`custom_build` = 自行编译后打包 |
| **kernel_repo / kernel_branch / kernel_config** | `ianchb/sm8550-mainline` / `sheng-7.2.2` / `sm8550.config` | 仅 `custom_build` 使用 |
| **firmware_repo / firmware_branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源（构建时打成 tar.zst 供 makepkg 离线使用） |
| **rootfs_size** | `10G` | 镜像初始大小；构建后收缩，首启由 `x-systemd.growfs` 扩到分区实际大小 |
| **shrink_image** | `true` | 构建后 `e2fsck -fy` + `resize2fs -M` 收缩镜像 |
| **upload_artifacts** | `true` | 设为 `false` 只验证流程、不产出 Artifact |

## 实现要点

**两段式流水线**

1. `_packages.yml`（`workflow_call`，10 个作业）在 `ubuntu-24.04-arm` 上：
   下载 ALARM tarball → 解包成可复用的 chroot（`/mnt/alarm`，用 `actions/cache` 缓存 **tar.zst 快照**）→
   `pacman-key --init/--populate archlinuxarm` → `pacman -Syu` → 装 `base-devel` →
   建非 root 用户 `builder`（`makepkg` 禁止以 root 运行）→ `makepkg` 构建每个设备包。
2. `rootfs.yml` 组装镜像：建 ext4 镜像 → 解包 ALARM tarball → 挂 chroot →
   镜像内 6 个阶段（基础包 / 桌面 / 浏览器 / 设备包 / 系统配置 / 校验）→ 卸载 → 收缩 → 上传。

**Debian 包原生重打包**：`packages/_shared/deb2pkg.sh` 把上游 `.deb` 的载荷做 Debian→Arch 布局修正
（`/bin`、`/sbin`、`/lib` → `/usr/...`，丢弃 `/etc/init.d`），元数据（包名/版本/依赖）全部由
PKGBUILD + `makepkg` 生成，`postinst` 改写为 pacman 的 `.INSTALL`。
6 个 `xiaomi-*` 包就是这条路径；源码型包（`fastrpc`、`libssc`、`iio-sensor-proxy`、`sheng-devauth`、内核）由 PKGBUILD 自行编译。

**包名与替换关系**

- `iio-sensor-proxy` → **`iio-sensor-proxy-sheng`**（`provides/conflicts=('iio-sensor-proxy')`），
  避免与 ALARM extra 的同名包做版本比较；`libssc` 沿用原名（带 QRTR 等待补丁）。
- `linux-xiaomi-sheng` 声明 `provides/conflicts=('linux' 'linux-aarch64')`；
  `firmware-xiaomi-sheng` 声明 `provides/conflicts/replaces=('linux-firmware')`。

**踩过并已修掉的 ALARM 侧坑（维护时请勿回退）**

| 现象 | 原因 | 处置 |
|---|---|---|
| chroot 内 `Could not resolve host` | ALARM rootfs 的 `/etc/resolv.conf` 是指向 `/run/...` 的悬空软链，`cp` 跟随软链失败 | 先 `rm -f`，宿主是 stub 时改用公共 DNS |
| `could not determine cachedir mount point` + 误报"磁盘空间不足" | pacman 7 的下载沙箱在 chroot 内不可用；`CheckSpace` 需要可判定的挂载点而 `/etc/mtab` 不是 `/proc/self/mounts` 软链 | 修 `/etc/mtab` 软链；注释 `DownloadUser` + 加 `DisableSandbox`；构建 chroot 注释 `CheckSpace`（`--disable-sandbox` 开关 ALARM 并不支持） |
| makepkg 里 `/dev/null: Permission denied` → `Failed to create the directory $BUILDDIR` | 缓存快照前会卸载 virtfs，而 ALARM tarball 自带的 `/dev` 对非 root 不可用 | `21-build-pkg.sh` 自己挂 `/proc /sys /dev /dev/pts` |
| fastrpc / libssc 报 `No such file or directory` | PKGBUILD 用 `$startdir/../../patches/...`，但 `patches/` 没被拷进 chroot | 构建前把 `patches/` 同步到 `/build/patches` |
| 明明 `Finished making: ...` 却找不到产物 | **ALARM 的产物扩展名是 `.pkg.tar.xz`**（Arch 是 `.zst`），而所有匹配都写成 `.zst`；且 `PKGDEST` 不在 `$startdir` | 全部改为 `*.pkg.tar.*`；并显式强制 `PKGDEST=/build/pkgs-out` |
| `xiaomi-pen-status` 依赖解析失败 | 它依赖同批次稍后才构建的 `xiaomi-sheng-thp` | 构建后把包装入 chroot + 多轮重试；纯重打包包用 `makepkg -df` 跳过依赖检查 |
| `pacman -U` 报 `unresolvable package conflicts` | 与 ALARM 预装的 stock `linux-aarch64` 冲突，`--noconfirm` 对"是否移除"默认回答 N | 安装前显式 `pacman -Rdd` 掉 `libssc` / `iio-sensor-proxy` / `linux-firmware*` / `linux-aarch64` |

## 仓库结构

```
.github/workflows/
  _packages.yml        workflow_call：10 个作业（内核 prebuilt/custom + 7 个设备包 + xiaomi-* 下载与重打包）
  rootfs.yml           主编排：参数解析 + 组装 rootfs.img / boot.img
  validate.yml         CI 静态自检：bash -n（含 15 个 PKGBUILD）/ shellcheck / YAML 解析 / 目录树
packages/
  _shared/deb2pkg.sh   deb → pacman 载荷原生化（布局修正 + 依赖映射报告）
  linux-xiaomi-sheng/{prebuilt,custom}/  内核包（重打包 ianchb 的 deb / 打包自编译产物）
  alsa-xiaomi-sheng/ sheng-sensors/ sheng-devauth/ firmware-xiaomi-sheng/
  fastrpc/ libssc/ iio-sensor-proxy/ xiaomi-*/         共 15 个 PKGBUILD
scripts/
  common/  host/  in-chroot/  lists/  packages/
patches/ mkbootimg sm8550.config
```

## 已知限制

- **不生成 initramfs**（与上游一致）：内核 `sm8550.config` 中 `CONFIG_EXT4_FS=y`，可直接挂载 ext4 根分区启动。
  副作用是 Plymouth splash 在没有 initramfs 时不会显示；`mkinitcpio` 已随包安装，需要时可自行生成
  （并用 `mkbootimg --ramdisk` 打进 `boot.img`）。
- **AUR 包不参与构建**：`plymouth-theme-breeze`、`kde-config-plymouth` 只在 AUR，
  构建里按 best-effort 尝试并跳过；`plymouth` 本体已确认安装（`90-verify.sh` 在 `quiet_boot=true` 时硬校验）。
- **可选包按 best-effort 安装**：桌面/字体等包若在 ALARM 缺失或改名，只会在日志里出现"跳过"告警；
  核心包（`gnome-shell` / `plasma-workspace` / `plasma-mobile`）由 `90-verify.sh` 硬校验。
- **固件替换语义**：`firmware-xiaomi-sheng` 替换 `linux-firmware*`（与 Debian 版同义）。
  ALARM 把 Adreno（a740）固件放在 `linux-firmware-qcom` 里，而它只是 `linux-firmware` 的 optdepend——
  若 `sheng-firmware` 未覆盖该固件，首启 `dmesg` 会报缺固件，可在设备上单独安装 `linux-firmware-qcom`（先确认无文件冲突）。
- **SDDM 的 plasma-mobile 会话名**写的是 `plasmamobile`；若停留在登录界面，用
  `ls /usr/share/wayland-sessions/` 核对实际名称。
- **尚未真机验证**：镜像产出了，但未在设备上刷写与验收。

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

`firmware-xiaomi-sheng` 在本仓库内只有 PKGBUILD，**固件二进制在构建时从上游 `sheng-firmware`
下载**，本仓库不重新分发；这些固件版权归高通 / 小米等各自权利人，仅用于在自有设备上运行 Linux。

## 致谢

- **map220v** — TWRP、主线内核移植与大量设备适配
- **alghiffaryfa19** — 上游原始构建脚本
- **ianchb** — [debian-sheng](https://github.com/ianchb/debian-sheng) 与 `xiaomi-*` 设备功能包
- **Dylan Van Assche** — `libssc` 与 `iio-sensor-proxy` 的 SSC 后端
