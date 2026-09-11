# 构建排错与首启验收手册（Arch Linux ARM）

本项目的流水线已在 GitHub Actions 上跑通并产出镜像（见 README 的"已验证的构建"）。
本文用于**排错**与**真机验收**，按出现顺序列出每一步的"正常表现 / 失败含义 / 处置"。

## 0. 触发前

- 先在 Settings → Secrets 里设置 `ROOTFS_PASSWORD`（未设置则镜像密码为默认值 `password`）。
- 磁盘是硬约束：标准 arm64 runner 约 14 GB。ALARM tarball（≈792 MiB）+ 解包后的 chroot +
  10 GiB 镜像同时存在；若出现 `No space left on device`，把 `rootfs_size` 降到 `6G`
  （首启 `x-systemd.growfs` 仍会扩到分区实际大小）。
- 首次运行会为每个包作业各下载一次 ALARM tarball；成功后会保存 chroot 快照缓存（`actions/cache`），后续作业/运行直接复用。

## 1. 日志观测点

### 设备包作业（`_packages.yml`）

| 步骤 | 正常表现 | 失败含义与处置 |
|---|---|---|
| Prepare ALARM Chroot | 下载 tarball → 解包 → 写 mirrorlist → 修 `/etc/mtab` → 关闭 pacman 下载沙箱 → `pacman-key --init/--populate` → `pacman -Syu` → 装 `base-devel` → 建 `builder` 用户 | ① 下载失败：官方是 HTTP GeoIP 重定向，候选里含国内镜像；② `pacman -Syu` 失败多为镜像临时问题，重跑；③ 出现 `.pacnew` 会**故意失败**，提示 ALARM 的默认配置已变动，需人工核对 |
| Package Kernel (prebuilt) | 下载 `linux-xiaomi-sheng*.deb` → 重打包成 pacman 包 | 报"载荷中没有 /usr/lib/modules/<kver>"= release 资产与预期不符 |
| Build libssc | `prepare()` 应用 `wait_for_qmi_service.patch`，随后校验重试逻辑存在 | 补丁打不上且上游也无重试逻辑时**故意失败**：把 `LIBSSC_REPO` 指向带 `#tag=v0.4.2` 的地址，或重做补丁 |
| Build iio-sensor-proxy | 先用 `PKG_PREINSTALL` 装上本仓库构建的 `libssc` 再编译 | 若链到 ALARM 官方的 libssc，行为不一致（作业顺序已保证不会） |
| Package firmware / alsa / sensors / devauth | `makepkg` 成功并上传 `*-pkg` | 见 README"踩过并已修掉的 ALARM 侧坑" |
| Fetch & Repack xiaomi-* | 下载 6 个 deb → 按 `source=()` 的规范名放进各包目录 → `makepkg -df` 重打包 | 某个上游仓库没有 release 资产时该包缺失，最终由组装阶段的逐包断言报出 |

### 组装作业（`rootfs.yml`）

| 步骤 | 正常表现 | 失败含义与处置 |
|---|---|---|
| Verify Collected Packages | **逐包断言**必需包（含 `iio-sensor-proxy-sheng`） | 缺哪个会直接点名 |
| Bootstrap Arch Linux ARM | 解包 ALARM → 写 mirrorlist → 校验 `Architecture = aarch64` 与 `[core] [extra] [alarm]` → keyring → `pacman -Sy` | 与 Prepare 同理；`.pacnew` 会故意失败 |
| `[chroot] Install Base Packages` | `pacman -Syu` + 基础包 | — |
| `[chroot] Install Desktop` | 很快（pacman 并行下载，Plasma 约 1 分钟） | 可选包缺失只告警；核心包由校验兜底 |
| `[chroot] Install Device Packages` | `移除 …`（libssc / iio-sensor-proxy / linux-firmware* / linux-aarch64）→ `pacman -U` 成功 → `depmod` → enable 传感器与 devauth 服务 | ① 报**文件冲突**：还有 `linux-firmware*` 分包没被移除；② 报**冲突**且提到 `linux-aarch64`：stock 内核没被移除；③ 报**降级**：本地 `libssc` 版本低于 ALARM（已用 `-Rdd` 规避） |
| `[chroot] Verify Image` | 全部 `[ OK ]`：`modules.dep/alias`、fstab、locale、设备关键文件、`pacman -Q` 逐包、wheel/sudoers、自动登录、显示管理器与 NetworkManager enabled | 按提示定位 |
| Clean pacman cache | 清 `/var/cache/pacman/pkg` | 必须在 verify 之后（`pacman -Scc` 会清掉 sync 数据库） |

**耗时基线**：整轮约 10 分钟（含 10 个包作业），组装作业约 5 分钟。

## 2. 刷写

前置：已解锁 BL、TWRP 已装、宿主机 `fastboot` 可用。双系统请先在 TWRP 里用 `parted` 缩小 `userdata`
并在末尾新建 `linux` 分区（概念参考 [alghiffaryfa19/Linux-xiaomi-sheng](https://github.com/alghiffaryfa19/Linux-xiaomi-sheng)）。

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

> ⚠️ 刷写会修改设备分区，请先备份。单系统模式（`boot_mode=single (userdata)`）会清空原有系统。

## 3. 首启验收判据

1. **根分区扩容**：`df -h /` 应接近 `linux` 分区大小（ext4 + `x-systemd.growfs`；注意 f2fs 不支持 growfs）。
2. **内核与模块**：`uname -r` 与 `/usr/lib/modules/` 一致；`pacman -Q linux-xiaomi-sheng`。
3. **固件**：`dmesg | grep -i -E 'firmware|adreno|ath12k|fastrpc'`。
   ALARM 把 Adreno（a740）固件放在 `linux-firmware-qcom`；若 `sheng-firmware` 未覆盖，可在设备上
   单独安装 `linux-firmware-qcom`（先确认与本仓库固件包无文件路径冲突）。
4. **传感器链路**：`systemctl status adsprpcd-sensorspd iio-sensor-proxy`；
   `pacman -Q iio-sensor-proxy-sheng libssc`；`monitor-sensor` / `ssccli` 有输出。
5. **桌面**：`systemctl get-default` = `graphical.target`；自动登录看 `/etc/gdm/custom.conf` 或 `/etc/sddm.conf.d/autologin.conf`。
   若停在登录界面，核对 SDDM 的 `Session=`（本项目写的是 `plasmamobile`），用 `ls /usr/share/wayland-sessions/` 确认。
6. **网络**：`nmcli` 能看到 WCN7850；`rfkill list` 无硬阻塞。
7. **Arch 特有检查**：`pacman -Q` 能查到全部本地包（`linux-xiaomi-sheng`、`firmware-xiaomi-sheng`、
   `alsa-xiaomi-sheng`、`sheng-sensors`、`sheng-devauth`、`fastrpc`、`libssc`、`iio-sensor-proxy-sheng`、6 个 `xiaomi-*`）。
8. **6 个 `xiaomi-*` 功能**：MiPPS 快充协商、关机充电屏、触控/手写笔、手写笔蓝牙状态、TEE 指纹、官方键盘麦克风指示灯。

## 4. 常见问题速查

| 症状 | 可能原因 | 处置 |
|---|---|---|
| `No space left on device` | 14 GB 磁盘 + 10 GiB 镜像 | 把 `rootfs_size` 降到 `6G` |
| chroot 内 DNS 失败 | `resolv.conf` 悬空软链 | 已修（见 README 的坑表）；若再出现，检查宿主 `/etc/resolv.conf` 是否可用 |
| `could not determine cachedir mount point` | pacman 沙箱 / CheckSpace / mtab | 已修；若再出现，检查 `/etc/mtab` 是否指向 `/proc/self/mounts` |
| makepkg 报 `/dev/null: Permission denied` | chroot 未挂 virtfs | 已修（`21-build-pkg.sh` 会自己挂 `/proc /sys /dev`） |
| 构建成功但找不到 `.pkg.tar.*` | ALARM 产物是 `.xz` 而非 `.zst`；`PKGDEST` 位置 | 已修（全部用 `*.pkg.tar.*`，并强制 `PKGDEST=/build/pkgs-out`） |
| `unresolvable package conflicts (linux)` | 与 stock `linux-aarch64` 冲突 | 已修（安装前 `-Rdd` 移除） |
| 首启没有开机画面 | 未生成 initramfs | 与上游一致的行为；需要时在设备上 `mkinitcpio -P` 并用 `mkbootimg --ramdisk` 重打 `boot.img` |

## 5. 常用排查命令

```bash
# 挂载产物镜像检查真实状态
sudo mount -o loop rootfs.img /mnt && sudo chroot /mnt /bin/bash

# 包层面
pacman -Q | grep -E 'iio-sensor|libssc|firmware-xiaomi|linux-xiaomi'
pacman -Qi iio-sensor-proxy-sheng

# 设备侧
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy -u NetworkManager --no-pager
```
