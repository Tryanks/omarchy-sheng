# 与上游 debian-sheng 的功能对照（Arch Linux ARM 版）

> 上游基准：`ianchb/debian-sheng` 的 `.github/workflows/rootfs.yml`（master，7 个作业）。
> 本表逐条列出上游每个步骤在本仓库的落点，用于验收"全量对齐"。
> 生成方式：对照上游 `rootfs.yml` 全文逐项核对本仓库文件，非凭印象填写；
> 输入项对齐情况由脚本对两个仓库的 `workflow_dispatch` 做差集核对（见文末"验收状态"）。

## 一、workflow_dispatch 输入项

| 上游输入 | 本仓库 | 说明 |
|---|---|---|
| `distro_suite`（trixie/forky） | — | Arch 是滚动发行版，`pacman -Syu` 取最新，无版本代号可填 |
| `desktop`（GNOME/KDE Plasma/server） | ✅ 同名同选项 | ✅ |
| `plasma_mobile` | ✅ | ✅ |
| `autologin` | ✅ | ✅ |
| `username` | ✅ | ✅ |
| `hostname` | ✅ | ✅ |
| `language`（10 个选项） | ✅ 同 10 项 | ✅ |
| `boot_mode`（single/dual/custom） | ✅ 同名同选项 | 第三个选项字面量同为 `custom` |
| `quiet_boot` | ✅ | ✅ |
| `custom_partition` | ✅ | ✅ |
| `kernel_source`（prebuilt/custom_build） | ✅ | ✅ |
| `kernel_repo` / `kernel_branch` / `kernel_config` | ✅ | 默认值同上游（`sheng-7.2.2` / `sm8550.config`） |
| `firmware_repo` / `firmware_branch` | ✅ | 默认 `ianchb/sheng-firmware` / `master` |
| — | **新增** `rootfs_size`、`shrink_image`、`upload_artifacts`、`browser` | 前两项是上游缺口补强；`upload_artifacts` 合并了上游 `rootfs-lite.yml` 的"测试不产出"用途；`browser` 便于跳过浏览器（Arch 官方仓库的 firefox 是普通包，默认 `firefox`） |

合计 19 个输入项（上游对齐 15 个 + 新增 4 个）。与姊妹项目 ubuntu-sheng 的唯一差异是
`ubuntu_series`（Arch 侧不存在），其余输入项名称、类型、默认值完全一致。

## 二、设备功能包构建（`_packages.yml`，10 个作业）

| 上游作业 | 本仓库 job | 实现脚本 / 包目录 |
|---|---|---|
| `build-kernel`（custom_build） | `build-kernel` | `scripts/host/21-build-pkg.sh` + `packages/linux-xiaomi-sheng/custom/` |
| — （上游仅 pkg.tar/deb 直传） | **新增** `build-kernel-prebuilt` | 下载内核 deb，**重打包**为 `linux-xiaomi-sheng` pacman 包（`packages/linux-xiaomi-sheng/prebuilt/`） |
| `build-fastrpc` | `build-fastrpc` | `packages/fastrpc/`（源码在 chroot 内 `makepkg`） |
| `build-libssc` | `build-libssc` | `packages/libssc/`（含 `patches/wait_for_qmi_service.patch`） |
| `build-iio-sensor-proxy` | `build-iio-sensor-proxy` | `packages/iio-sensor-proxy/` → 产出 `iio-sensor-proxy-sheng` |
| `build-sheng-sensors` | `build-sheng-sensors` | `packages/sheng-sensors/` |
| `build-sheng-devauth` | `build-sheng-devauth` | `packages/sheng-devauth/` |
| Package alsa-xiaomi-sheng | `package-alsa` | `packages/alsa-xiaomi-sheng/` |
| Package firmware-xiaomi-sheng | `package-firmware` | `packages/firmware-xiaomi-sheng/` |
| 6 × `gh release download` xiaomi-* | `fetch-xiaomi-debs` | `scripts/packages/fetch-xiaomi-debs.sh` + `scripts/host/22-repack-deb.sh` |

与上游最本质的区别：**上游把 `.deb` 直接铺进文件系统，本仓库全部产出真正的 pacman 包**
（15 个 PKGBUILD，见 `packages/`），因此镜像里 `pacman -Q` 能看到、能被依赖解析、能卸载。

## 三、rootfs 组装步骤

| 上游步骤 | 本仓库落点 | 备注 |
|---|---|---|
| Verify Arguments（密码警告、custom 组合校验） | `rootfs.yml` → Verify Arguments | 同规则，另加 username/hostname 字符校验 |
| Parse Partition Label（label / quiet / boot_img_pattern） | `rootfs.yml` → Parse Arguments | 同逻辑 + 追加 `desktop_slug` |
| Install Build Tools（debootstrap git curl） | `rootfs.yml` → Install Host Tools | 改为 `curl git gh e2fsprogs xz-utils zstd libarchive-tools rsync gzip`（无 debootstrap，改用 ALARM tarball） |
| `[Prebuilt]` Download Kernel | `scripts/host/10-fetch-kernel.sh` | 同样的 `gh release list/download`，同样的 4 个 boot 变体名 |
| `[Custom]` Download Kernel Package/Image | `rootfs.yml` → download-artifact ×2 | ✅ |
| Create RootFS Image（`truncate` + `mkfs.ext4`） | `scripts/host/00-prepare-image.sh` | 额外加 `-L rootfs` 卷标；仍是无分区表镜像 |
| Mount RootFS Image | 同上（loop mount） | ✅ |
| Run Debootstrap | `scripts/host/01-bootstrap-arch.sh` | 改为解包 `ArchLinuxARM-aarch64-latest.tar.gz` + 写 mirrorlist + keyring + `pacman -Sy` |
| Mount Virtual File Systems（bind /dev,/dev/pts,proc,sys + resolv.conf） | `scripts/host/02-mount-chroot.sh` | 额外把脚本与 `pkgs/` 拷入镜像 |
| Install Base Packages | `scripts/in-chroot/10-base.sh` | ✅ |
| Use Upstream Regulatory Database | 同上 | 同样的 `update-alternatives --set regulatory.db` |
| Install Plymouth（quiet 且非 server） | `scripts/in-chroot/20-desktop.sh` | ✅ |
| Install All .deb Packages | `scripts/in-chroot/30-device-packages.sh` | 改为 `pacman -U`；上游 `\|\| apt-get install -f -y` 后静默继续，这里失败会终止 |
| Fix Permissions（adsprpcd/iio-sensor-proxy/monitor-sensor/ssccli） | 同上 | ✅ 同样的 4 个路径 |
| Enable Sensor Services | 同上 | **修正上游拼写**：真实 unit 是 `adsprpcd-sensorspd.service`（a-d-s-p-r-p-c-d），上游 enable 写成 `adsrpcd-…`（少一个 rp）→ 上游那个 unit 其实永远没被启用。本仓库写死正确文件名，并在 `90-verify.sh` 里校验"已 enable"而不只是"文件存在" |
| — | **新增** `depmod -a <kver>` + 校验 `modules.dep` | 上游全程无 depmod |
| Set Hostname（/etc/hostname + /etc/hosts 127.0.1.1） | `scripts/in-chroot/40-system-config.sh` | ✅ |
| Configure Locale | 同上 | 同语义，写 `/etc/locale.conf`（Arch 无 `/etc/default/locale`） |
| Create User（`useradd -m -s /bin/bash -G sudo`） | 同上 | 改为加入 `wheel` 组 + 写 `/etc/sudoers.d/10-wheel`（Arch 无 sudo 组） |
| Set Passwords（用户与 root 同密码，空则 `password`） | 同上（密码经 600 权限文件传入，不再走命令行） | ✅ |
| Install GNOME / KDE Plasma | `scripts/in-chroot/20-desktop.sh` | 包名按 ALARM 仓库名重写；`kde-config-plymouth` / `plymouth-theme-breeze` 只在 AUR，best-effort 跳过 |
| Install KDE Plasma Plymouth Settings | 同上 | ✅ |
| Configure GDM / SDDM (+Autologin) | `scripts/in-chroot/40-system-config.sh` | Arch 的 GDM 用 `/etc/gdm/custom.conf`（非 `/etc/gdm3/`）；SDDM 仍是 `/etc/sddm.conf.d/autologin.conf`；`90-verify.sh` 校验自动登录项存在 |
| Enable NetworkManager | 同上 | ✅ |
| Configure fstab（`PARTLABEL=<label> / ext4 defaults,x-systemd.growfs 0 1`） | 同上 | ✅ 完全一致 |
| Clean APT Cache + 删 resolv.conf | `rootfs.yml` → Clean pacman cache + Cleanup Host Files | 改为 `pacman -Scc`，且放在 verify **之后**（避免清掉 sync 数据库影响校验） |
| Unmount Virtual File Systems（`if: always()`） | `scripts/host/03-umount-chroot.sh` + workflow `if: always()` | ✅（不再连带卸载镜像本身，避免 e2fsck 拒绝运行） |
| Unmount Image & Set UUID（`tune2fs -U ee8d3593-…`） | `scripts/host/04-finalize-image.sh` | 同 UUID；**新增** `e2fsck -fy` + `resize2fs -M` + 截断文件 |
| `[Custom]` Generate boot.img（本地 mkbootimg） | `scripts/host/11-make-bootimg.sh` | cmdline、base/kernel_offset/tags_offset/pagesize 与上游逐字一致 |
| Upload RootFS Image / Boot Image | `rootfs.yml` → upload-artifact ×2 | `retention-days: 14`、`compression-level: 1` 同上游 |

## 四、明确记录的行为差异

1. **设备包一律原生打包**：上游是"编出来 / 下下来就是最终载荷"；本仓库每类载荷都有 PKGBUILD，
   deb 形式的第三方包（内核、`xiaomi-*`）经 `packages/_shared/deb2pkg.sh` 做 Debian→Arch 布局修正后重打包。
   代价是包名/依赖需要手工映射（见各 PKGBUILD 头部的"依赖映射"注释），收益是可被 pacman 管理。
2. **不生成 initramfs**：与上游一致（内核 `CONFIG_EXT4_FS=y`，无需 initramfs）。副作用是 `custom_build` 下 plymouth splash 不会真正显示。
3. **失败即终止**：包安装失败、`modules.dep` 缺失、fstab 不符、关键文件缺失、必需包未收集齐等都会让构建失败，而不是产出静默坏镜像（上游多处为静默继续）。
4. **不涉及 snap**：Arch 默认没有 snapd，因此没有 Ubuntu 侧的 `15-nosnap.sh` 与相关校验。
5. **磁盘策略更保守**：runner 磁盘约 14 GB，组装时的 `rootfs_size` 若设得过大可能 `No space left on device`；
   默认 `10G` 已验证可用（见 README 的实测数据）。

## 五、验收状态

- **输入项对齐**：已用脚本对两个仓库的 `workflow_dispatch` 输入做差集核对 —— 上游对齐的 15 项名称与默认值一致，
  与 ubuntu-sheng 相比仅差 `ubuntu_series`（Arch 无此概念），`browser` 默认值不同（Arch 为 `firefox`）。
- **构建实测**：Arch / server 与 Arch / KDE Plasma 两条配置已在 GitHub Actions 上跑通并产出镜像，
  见 README"已验证的构建"表（含 run 链接与产物大小）。
- **尚未验证**：镜像**未在真机上刷写**。刷写命令、首启验收判据与排错步骤见
  [`troubleshooting.md`](troubleshooting.md)。
