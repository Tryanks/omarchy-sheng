# 首次构建清单（Arch 版）

> 本仓库全部代码都是**静态编写**的（开发环境禁止执行 bash/git/tar/python），
> 且 Arch 侧的构建机制（宿主机上做 ALARM chroot + makepkg）比 Ubuntu 侧复杂，
> 因此**第一次构建请按本清单逐段核对日志**。

## 0. 先跑静态自检

push 后 `.github/workflows/validate.yml` 自动触发：

- 全部 `.sh` **与 15 个 `PKGBUILD`**（PKGBUILD 本身就是 bash）的 `bash -n`
- `shellcheck --severity=warning`
- 每个 PKGBUILD 必须有 `pkgname/pkgver/pkgrel/pkgdesc/arch`，且 `arch=('aarch64')`
- 解析 `.github/workflows/*.yml`
- 关键文件存在性（`mkbootimg`、`sm8550.config`、`patches/wait_for_qmi_service.patch`、`patches/adsprpcd-sensorspd.service`、内核 PKGBUILD 目录）

## 1. 准备

1. 推到你自己的 GitHub，启用 Actions（`ubuntu-24.04-arm`：public repo 免费，**4 vCPU / 16 GB / 14 GB 磁盘**）。
2. 设置 secret `ROOTFS_PASSWORD`（不设则镜像密码为默认值 `password`，日志有 `::warning::`）。
3. **磁盘是硬约束**：ALARM tarball（~792 MiB）+ 解包后的 chroot + 10 GiB 镜像同时存在。
   若日志出现 `No space left on device`，把 `rootfs_size` 从 `10G` 降到 `6G`
   （首启 `x-systemd.growfs` 仍会把根分区扩到实际大小）。

## 2. 第一次构建：建议参数

| 输入 | 建议 | 理由 |
|---|---|---|
| `upload_artifacts` | `false` | 先验证流程 |
| `desktop` | `KDE Plasma`（默认） | 一次只改一个变量 |
| `quiet_boot` | `false` 先试 | 排除 plymouth 变量 |
| `kernel_source` | `prebuilt`（默认） | `custom_build` 会多花 30–60 分钟编译内核 |

## 3. 构建日志里要盯的点

**设备包作业（`_packages.yml`，每个包一个作业）**

| 步骤 | 正常表现 | 失败/异常的含义与处置 |
|---|---|---|
| `Prepare ALARM Chroot` | 首次：下载 tarball → 解包 → `pacman-key --init/--populate archlinuxarm` → `pacman -Syu` → 装 `base-devel`；之后作业命中 `/mnt/alarm-chroot.tar.zst` 缓存 | ① 下载失败：官方是 HTTP GeoIP 重定向，候选里含清华镜像；② `pacman -Syu` 失败多为镜像临时问题，重跑；③ 空间不足见上文 |
| `Package Kernel (prebuilt)` | 下载 `linux-xiaomi-sheng*.deb` → 重打包成 pacman 包 | 报"载荷中没有 /usr/lib/modules/<kver>"说明 release 资产与预期不符 |
| `Build libssc` | `prepare()` 里应用 `wait_for_qmi_service.patch`，随后校验重试逻辑存在 | **补丁打不上且上游也没有重试逻辑时会故意失败**：把 `LIBSSC_REPO` 指向带 `#tag=v0.4.2` 的地址，或重做补丁 |
| `Build iio-sensor-proxy` | 因 `PKG_PREINSTALL` 先装上本仓库的 `libssc` 再构建 | 若链到了 ALARM 官方的 libssc 0.4.4，行为会不一致（作业顺序已保证不会） |
| `Fetch & Repack xiaomi-*` | 下载 6 个 deb → `22-repack-deb.sh` 按 `source=()` 的规范名放进 `packages/<pkg>/` → makepkg 重打包 | 某个上游仓库没有 release 资产时该包会缺失，verify 会给 `xiaomi-* 包少于 6 个` 警告 |

**组装作业（`rootfs.yml`）**

| 步骤 | 正常表现 | 失败/异常的含义与处置 |
|---|---|---|
| `[Prebuilt] Download Kernel & boot.img` | release tag + `boot_sheng_*.img` + `linux-xiaomi-sheng*.deb` | 见 Ubuntu 版同名的处置 |
| `Verify Collected Packages` | **逐包断言**必需包名（含 `iio-sensor-proxy-sheng`） | 缺哪个会直接点名 |
| `Bootstrap Arch Linux ARM` | 解包 ALARM → 写 mirrorlist → keyring | 与 Prepare 同理 |
| `[chroot] Install Base Packages` | `pacman -Syu` + 基础包 | — |
| `[chroot] Install Device Packages` | `移除仓库版本的 libssc` → `移除基础镜像预装的固件包（N 个）` → `pacman -U` 成功 | ① 报**文件冲突**：还有 `linux-firmware*` 分包没被移除（脚本已 `-Rdd` 全部同名包，若仍冲突请把冲突路径贴出来）；② 报**降级**：本地 `libssc` 版本低于 ALARM（已用 `-Rdd` 规避） |
| `[chroot] Verify Image` | 全部 `[ OK ]`：`pacman -Q` 逐包、`modules.dep/alias`、fstab、locale、设备关键文件、wheel/sudoers、自动登录、显示管理器与 NetworkManager enabled | 按提示定位 |
| `[chroot] Clean pacman cache` | 清 `/var/cache/pacman/pkg` | 必须在 verify 之后（`pacman -Scc` 会清掉 sync 数据库） |

## 4. 与 Ubuntu 版最容易被误判为 bug 的 5 处差异

1. **没有 `15-nosnap`**：Arch 官方仓库不提供 snapd，verify 里只做"不应出现 snap"的防回归检查。
2. **没有 `policy-rc.d`**：那是 dpkg 机制；pacman 的 `.INSTALL` 约定用 `[ -d /run/systemd/system ]` 守卫。
3. **显示管理器是 `gdm` + `/etc/gdm/custom.conf`**（Ubuntu 是 `gdm3` + `/etc/gdm3/custom.conf`）。
4. **用户组是 `wheel` + `/etc/sudoers.d/10-wheel`**（Ubuntu 是 `sudo` 组）；locale 只写 `/etc/locale.conf`。
5. **内核包会替换 ALARM 预装的 stock `linux-aarch64`**（`provides/conflicts=('linux' 'linux-aarch64')`）；
   `iio-sensor-proxy` 包名是 **`iio-sensor-proxy-sheng`**（避免与 ALARM extra 的同名包做版本比较）。

## 5. 刷写（B 槽 + `linux` 分区；双系统请在 TWRP 内先分好区）

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

## 6. 首启后的验收判据

1. **扩容**：`df -h /` 接近 `linux` 分区大小（ext4 + `x-systemd.growfs`；注意 **f2fs 不支持 growfs**）。
2. **内核/模块**：`uname -r` 与 `/usr/lib/modules/` 一致；`pacman -Q linux-xiaomi-sheng`。
3. **固件**：`dmesg | grep -i -E 'firmware|adreno|ath12k|fastrpc'`。
   **Adreno a740 的 `a740_sqe.fw` / `a740_zap.mbn` 在 ALARM 属 `linux-firmware-qcom`**，
   本仓库的固件包若未覆盖它，GPU 会缺固件 —— 必要时在设备上单独安装 `linux-firmware-qcom`
   （先确认与本包无文件路径冲突）。
4. **传感器**：`systemctl status adsprpcd-sensorspd iio-sensor-proxy`；`pacman -Q iio-sensor-proxy-sheng libssc`。
5. **桌面**：`systemctl get-default` = `graphical.target`；自动登录看 `/etc/gdm/custom.conf` 或 `/etc/sddm.conf.d/autologin.conf`。
   **若停在登录界面**：核对 SDDM 的 `Session=` 名（本仓库写的是 `plasmamobile`），用 `ls /usr/share/wayland-sessions/` 确认。
6. **网络**：`nmcli` 能看到 WCN7850。
7. **6 个 `xiaomi-*` 功能**：MiPPS 快充、关机充电屏、触控/手写笔、手写笔蓝牙、TEE 指纹、官方键盘麦克风指示灯。

## 7. 最可能需要调整的三处

| 事项 | 位置 | 判据 |
|---|---|---|
| 桌面/字体等可选包在 ALARM 是否都存在 | `scripts/lists/*.list` | 桌面安装是 best-effort，日志里"跳过安装失败的包"清单 |
| GPU/WiFi 固件覆盖范围 | `packages/firmware-xiaomi-sheng/` + `scripts/in-chroot/30-device-packages.sh` | 首启 `dmesg` |
| `libssc` 本地版（0.4.x + 补丁）与 ALARM 官方 0.4.4 的 ABI | `packages/libssc/PKGBUILD` | `ldd` 与实机传感器是否工作 |

## 8. 排错命令

```bash
# 挂载产物镜像检查真实状态
sudo mount -o loop rootfs.img /mnt && sudo chroot /mnt /bin/bash
# 包层面
pacman -Q | grep -E 'iio-sensor|libssc|firmware-xiaomi|linux-xiaomi'; pacman -Qi iio-sensor-proxy-sheng
# 设备侧
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy -u NetworkManager --no-pager
```
