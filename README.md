# archlinux-sheng

> 本项目是把 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) 的构建逻辑移植到
> **Arch Linux ARM（aarch64）** 的**独立仓库**：用 GitHub Actions 为**小米平板 6S Pro
> （sheng / 高通 SM8550）**构建 rootfs，产出可直接 `fastboot` 刷写的 `rootfs.img` 与 `boot.img`。
>
> 结构与姊妹仓库 [ubuntu-sheng](../ubuntu-sheng) 一一对应（同样的脚本分层、同样的 workflow
> 输入项、同样的 artifact 命名规则），只把发行版相关部分换成 Arch：
>
> * **不生成 initramfs**（与上游 Debian 版一致）：内核 `sm8550.config` 里
>   `CONFIG_EXT4_FS=y`（ext4 内建）、`CONFIG_BLK_DEV_INITRD=y` 但 **未设**
>   `CONFIG_INITRAMFS_SOURCE`，因此可以直接挂载 ext4 根分区启动。
> * **没有 snap 相关步骤**：Arch 官方仓库不提供 snapd，因此本仓库没有
>   `15-nosnap.sh`，`browser` 默认值为 `firefox`（官方仓库就是普通 pacman 包）。
> * **所有设备功能包都是原生 pacman 包**（由 `makepkg` 生成，可 `pacman -Q/-R`），
>   而不是把 deb 摊开塞进镜像。

---

## 支持范围

| 项 | 说明 |
|---|---|
| 发行版 | **Arch Linux ARM**（aarch64，滚动更新，基线用官方 `ArchLinuxARM-aarch64-latest.tar.gz`） |
| 架构 | aarch64，包源使用 `mirror.archlinuxarm.org`（`Server = $mirror/$arch/$repo`） |
| 运行环境 | `ubuntu-24.04-arm`（**原生 arm64**，所以可以在宿主上原生 chroot 进 aarch64 的 Arch，**不需要 qemu/binfmt**） |
| 桌面环境 | KDE Plasma（含 `plasma-mobile` 选项）/ GNOME / server（无图形界面） |
| 启动方式 | `dual (linux)`（双系统，默认）/ `single (userdata)` / `custom`（自定义分区名） |
| 内核 | `prebuilt`（取 [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) 的最新 release）或 `custom_build`（自编译） |
| 设备功能包 | firmware、alsa UCM2、传感器（libssc + iio-sensor-proxy + SSC 注册表）、键盘认证、以及 6 个 `xiaomi-*` 包 |

## 快速开始

1. Fork 本仓库，在 **Actions** 页面启用 workflow。
2. 选择 **Build RootFS (Arch Linux ARM)** → **Run workflow**，按需填写参数（默认值即可直接构建）。
3. 构建完成后在该次运行的 **Artifacts** 中下载 `rootfs-arch-*` 与 `boot-arch-*`。
4. 刷写（与上游 `debian-sheng` 流程一致，假设使用 B 槽 + `linux` 分区）：

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

> 建议在仓库 Secrets 中设置 `ROOTFS_PASSWORD`（普通用户与 root 的密码）。
> 未设置时会回退到上游同样的不安全默认值 `password`，构建日志会给出警告。

## 参数说明（workflow_dispatch 输入项）

| 参数 | 默认 | 说明 |
|---|---|---|
| **desktop** | `KDE Plasma` | `GNOME` / `server`（无 GUI） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop` |
| **browser** | `firefox` | `none` = 不装浏览器；`firefox` = 装 Arch 官方仓库的 firefox（普通包） |
| **autologin** | `true` | 自动登录普通用户 |
| **username / hostname** | `username` / `xiaomi-sheng` | |
| **language** | `None (C.UTF-8)` | 选择后放开 `/etc/locale.gen`、`locale-gen`，并写 `/etc/locale.conf` |
| **boot_mode** | `dual (linux)` | 决定 fstab 的 `PARTLABEL=` 与使用哪个预编译 boot 镜像 |
| **custom_partition** | 空 | 仅 `boot_mode=custom` 使用，只允许字母数字与 `_ -` |
| **quiet_boot** | `true` | 安装 Plymouth，并选用 `*_plymouth.img`（server 模式忽略） |
| **kernel_source** | `prebuilt` | `custom_build` 时用 `kernel_repo/branch/config` 自行编译 |
| **kernel_repo / branch / config** | `ianchb/sm8550-mainline` / `sheng-7.2.2` / `sm8550.config` | |
| **firmware_repo / branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源（stage 成 `sheng-firmware.tar.zst` 后离线打包） |
| **rootfs_size** | `10G` | 初始大小；构建后收缩，首启靠 `x-systemd.growfs` 自动扩容 |
| **shrink_image** | `true` | 构建后 `e2fsck` + `resize2fs -M` 收缩镜像（上游没有这一步） |
| **upload_artifacts** | `true` | 测试构建可关闭，只验证流程而不产出 artifact |

> 与 ubuntu-sheng 的输入项差异只有两条：**去掉 `ubuntu_series`**（Arch 是滚动发行版，
> `pacman -Syu` 取最新），**`browser` 默认改为 `firefox`**。

## Arch 原生化重打包方案

Arch 与 Debian 的包模型不同（pacman 的 `.PKGINFO`/`.MTREE` vs dpkg 的 `DEBIAN/control`），
本仓库的原则是：**所有设备包都由 `makepkg` 生成真正的 pacman 包**，
deb 只作为「载荷来源」被解包，绝不把 deb 直接摊进镜像。

| 上游 deb 包 | 本仓库 Arch 包 | 构建方式 |
|---|---|---|
| `linux-xiaomi-sheng`（release 里的 deb） | `linux-xiaomi-sheng`（`prebuilt/`） | 解 deb 的 `data.tar` → 布局修正 → `makepkg`；`pkgver()` 从 deb 的 `control` 读版本 |
| （自编译内核） | `linux-xiaomi-sheng`（`custom/`） | `scripts/stage-kernel.sh` 编译并铺 `stage/`（`modules_install` + `Image.gz-dtb_sheng`），`makepkg` 打包 |
| `sheng-firmware` | `firmware-xiaomi-sheng` | `scripts/stage-firmware.sh` 把固件仓库打成 `sheng-firmware.tar.zst`，离线 `makepkg` |
| `alsa-xiaomi-sheng` | `alsa-xiaomi-sheng` | 仓库内 `payload/` 直接装（并重建 UCM 软链） |
| `sheng-sensors` | `sheng-sensors` | 仓库内 `payload/` 直接装；Debian 的 `postinst` 改写为 pacman `.INSTALL` |
| `sheng-devauth` | `sheng-devauth` | 源码 `make` 编译；服务由镜像内脚本 `systemctl enable` |
| `fastrpc`（aDSP RPC） | `fastrpc` | autotools 源码编译；`patches/adsprpcd-sensorspd.service` 由 PKGBUILD 装入 |
| `libssc` | `libssc` | meson 源码编译 + `patches/wait_for_qmi_service.patch`（QRTR 等待） |
| `iio-sensor-proxy`（SSC 后端） | **`iio-sensor-proxy-sheng`** | meson `-Dssc-support=enabled`；改名是为了不与 ALARM extra 里的同名包冲突，用 `provides`/`conflicts` 保持依赖可解析 |
| `xiaomi-mipps-auth` / `xiaomi-charger-mode` / `xiaomi-sheng-thp` / `xiaomi-pen-status` / `xiaomi-sheng-fingerprint` / `xiaomi-sheng-keyboard-helper` | 同名 pacman 包 | 下载上游 release 的 `*.deb`（`scripts/packages/fetch-xiaomi-debs.sh`），按各自的 PKGBUILD 重打包 |

### `packages/_shared/deb2pkg.sh` 的作用

它不是打包器，而是 **「.deb 载荷 → `$pkgdir`」的搬运与布局修正库**：

* 从 deb 里取出 `data.tar.*` 解到 `$pkgdir`（保留权限位，所有权交给 makepkg/fakeroot）；
* 修正 Debian 专有布局：`/bin` `/sbin` `/lib` → `/usr/bin` `/usr/lib`（Arch 自 `filesystem`
  2024 起没有独立的 `/bin`、`/sbin`），`/usr/sbin` → `/usr/bin`，丢弃 `/etc/init.d`；
* 额外提供 `bash deb2pkg.sh --report <deb>`，打印 deb 元数据与
  「Debian 依赖名 → Arch 包名」的建议映射（`libc6→glibc`、`libglib2.0-0t64→glib2`、
  `libqmi-glib5→libqmi` …），用于人工核对 `depends=` 是否写全；
* 包名 / 版本 / 依赖 / `.PKGINFO` / `.MTREE` **全部由 PKGBUILD 声明**，因此产物是
  真正的 pacman 包：`pacman -Q` 能查到、`pacman -R` 能卸、依赖能被 pacman 解析。

### Arch 侧依赖解析与两个「换包」点

* `pacman -U /tmp/pkgs/*.pkg.tar.zst` 会按 `.PKGINFO` 的 `depend` 解析依赖，缺依赖直接失败
  （不会像 `apt-get install /tmp/*.deb || apt-get install -f -y` 那样静默留在半配置状态）。
* ALARM extra 里已经有 `libssc 0.4.4-1` 与 `iio-sensor-proxy 3.9-1`，而本仓库要装自己
  构建的 `libssc`（带 QRTR 等待补丁）与 `iio-sensor-proxy-sheng`。pacman 默认拒绝「降级」，
  因此 `scripts/in-chroot/30-device-packages.sh` 会先 `pacman -Rdd libssc iio-sensor-proxy`
  把仓库版本移出（不删依赖），再安装本地包。
* **`linux-firmware*` 也必须先移除**：ALARM 的 `linux-firmware` 是元包（`linux-firmware-qcom`
  只在 optdepends 里），它拆出 `linux-firmware-atheros` 等分包，而分包里的
  `ath12k/WCN7850/hw2.0/*` 与本仓库 `firmware-xiaomi-sheng` 的文件路径重叠。
  pacman 在安装与元包冲突的包时**不会**顺带移除它的分包 → 会因文件冲突失败。
  因此同一脚本在安装前 `pacman -Rdd` 掉**全部** `linux-firmware*` 包，
  设备固件统一由 `firmware-xiaomi-sheng` 提供（与 Debian 侧「本包替换 linux-firmware」同义）。
* **stock 内核自动替换**：ALARM 的 rootfs tarball 预装 `linux-aarch64`（含 sm8550-mtp/qrd 的
  DTB，但**没有 xiaomi-sheng**）。`linux-xiaomi-sheng` 声明了
  `provides/conflicts=('linux' 'linux-aarch64')`，所以安装本仓库内核包时 pacman 会自动移除它。

## 仓库结构与 workflow

```
.github/workflows/
  _packages.yml   # workflow_call：全部设备功能包（pacman 包）构建作业
  rootfs.yml      # 主编排：参数解析 + 组装 rootfs.img / boot.img
scripts/
  common/         # ALARM 常量（tarball / mirror / arch）+ 日志工具（宿主与镜像内共用）
  host/           # 宿主阶段：
                  #   alarm-lib.sh        ALARM chroot 公共库（下载/解包/打包快照/chroot 执行）
                  #   00-prepare-image    建并挂载 rootfs.img
                  #   01-bootstrap-arch   解 ALARM tarball + 写镜像源 + pacman-key init
                  #   02-mount-chroot     挂虚拟文件系统 + 把脚本/包拷进镜像
                  #   03-umount-chroot    逆序卸载
                  #   04-finalize-image   卸载 → e2fsck → 收缩 → 固定 UUID
                  #   10-fetch-kernel     prebuilt：下载 boot.img 与内核 deb
                  #   11-make-bootimg     custom：本地 mkbootimg 生成 boot.img
                  #   20-alarm-chroot     宿主上准备可复用的 ALARM aarch64 构建 chroot
                  #   21-build-pkg        chroot 内以 builder 身份 makepkg（保留 packages/ 相对结构）
                  #   22-repack-deb       把 xiaomi-* 的 deb 交给各自 PKGBUILD 重打包
  in-chroot/      # 镜像内阶段（BUILD_DIR=/root/sheng-build）：
                  #   lib-pac.sh          pacman 封装 + 包列表读取
                  #   10-base             基础包（先 -Syu，再装 lists/base.list）
                  #   20-desktop          GNOME / KDE Plasma / plasma-mobile / server + plymouth
                  #   25-browser          firefox / none
                  #   30-device-packages  安装本地 pacman 包 + 权限 + depmod + enable 服务
                  #   40-system-config    hostname / locale / 用户 / DM 自动登录 / 网络 / fstab / 清理
                  #   90-verify           构建末尾硬校验
  lists/          # 包列表（一行一个包，# 注释）
  packages/       # 下载上游 xiaomi-* 的 deb（fetch-xiaomi-debs.sh）
  stage-kernel.sh / stage-firmware.sh   # 给 makepkg 准备离线载荷
packages/         # 全部 Arch 包（PKGBUILD，每个包一个目录；_shared/ 是公共库）
patches/ mkbootimg sm8550.config
```

## Arch 构建 chroot（makepkg 的前提）

`makepkg` 不能以 root 运行、而且必须在 Arch 环境里运行，所以每个包构建作业都会先执行
`scripts/host/20-alarm-chroot.sh`：

1. 在宿主上解包 ALARM tarball 到 `/mnt/alarm`（原生 aarch64，无需 qemu）；
2. 写 `mirrorlist`、`pacman-key --init` + `--populate archlinuxarm`、`pacman -Syu`、
   安装 `base-devel`（含 `fakeroot`）；
3. 创建非 root 用户 `builder`，并写 `/etc/sudoers.d/10-sheng-builder`（`NOPASSWD`）。

`scripts/host/21-build-pkg.sh` 随后：

* 把**整个 `packages/` 目录**拷进 chroot 的 `/build/packages/`（保留相对结构，因为
  PKGBUILD 会引用 `$startdir/payload`、`$startdir/../_shared/deb2pkg.sh`、
  `$startdir/../../patches/...`）；
* 把 workflow 下载的 deb（prebuilt 内核、`xiaomi-*`）同步到 `/build/pkgs`，
  再按 PKGBUILD 的 `source=()` 自动放到 `$startdir`，因此不需要人工改名；
* 以 `builder` 身份执行 `makepkg -f --noconfirm --nocolor`（macOS 风格的
  `su - builder -c "cd /build/packages/<pkg> && makepkg ..."`），
  makepkg 自己会在 `package()` 阶段调用 `fakeroot`；
* 把产出的 `*.pkg.tar.zst` 拷回宿主 `pkgs/`。

**增量复用与缓存**：

* `/mnt/alarm` 已经就绪时只做 `pacman -Syu` + 补齐依赖，不会重新解包、不重新 init 密钥环；
* 不同 job 之间（GitHub Actions 每个 job 都是新虚拟机）用 tarball 快照复用，
  workflow 里的缓存如下（`/mnt/alarm` 是 root:root，`actions/cache` 对目录不友好，
  快照更可靠）：

```yaml
- uses: actions/cache@v6
  with:
    path: /mnt/alarm-chroot.tar.zst
    key: alarm-chroot-v1-${{ runner.arch }}-${{ hashFiles('scripts/host/20-alarm-chroot.sh', 'scripts/common/distro-env.sh', 'scripts/host/alarm-lib.sh') }}
```

> **cache key 建议**：用固定前缀 `alarm-chroot-v1-` + runner 架构 + 上面三个脚本的
> `hashFiles`。**不要把会滚动的 `ALARM_TARBALL_URL` 内容 hash 进 key**（它的 tarball
> 每天变，缓存将永远不命中）；ALARM 基础环境本来就是滚动的，`pacman -Syu` 会把它对齐到最新。

### 为什么没有「一次构建全部包」的汇总作业

`_packages.yml` 为每个包保留独立作业（与 ubuntu-sheng 结构一一对应，失败定位精确、
并行度高），并**没有**再放一个 `build-pacman-packages` 汇总作业，原因有两条：

1. 它会与逐个作业完全重复（15 个包重建一遍，多花 30+ 分钟）；
2. 它必然失败：6 个 `xiaomi-*` 包与 prebuilt 内核包都声明 `source=("<pkgname>.deb")`，
   汇总作业里没有任何步骤提供这些 deb；`iio-sensor-proxy` 还要求先安装本仓库构建的
   `libssc`（否则会链到 ALARM 官方的 0.4.4）。这些载荷/顺序依赖只有专用作业才保证。

需要本地一次性排查时仍可用：`sudo scripts/host/21-build-pkg.sh --all`
（`--all` 会按目录名遍历，自动跳过需要先 stage 载荷的 `firmware-xiaomi-sheng`，
可用 `ALARM_SKIP_PKGS` 调整）。

## 与 ubuntu-sheng（以及上游 debian-sheng）的差异清单

1. **发行版基线**：`ubuntu-base` tarball + `apt` → `ArchLinuxARM-aarch64-latest.tar.gz` + `pacman`；
   Ubuntu 的 suite 代号映射（`26.04 (resolute)` 等）不再需要，因此去掉 `ubuntu_series` 输入。
2. **没有 snap 禁用层**：Arch 官方仓库不提供 snapd，因此没有 `15-nosnap.sh`、
   没有 `nosnap.pref`；`90-verify.sh` 只留一条「不应出现 snap/snapd」的防回归检查。
3. **没有 `policy-rc.d`**：那是 Debian `dpkg` 的机制。pacman 安装包时不会启动服务
   （chroot 里 systemd 没在跑），各包的 `.INSTALL` 自带 `[ -d /run/systemd/system ]` 守卫。
4. **镜像内用户组**：Ubuntu 用 `sudo` 组，Arch 用 `wheel` 组 + `/etc/sudoers.d/10-wheel`（mode 440）。
5. **locale**：Arch 只写 `/etc/locale.conf`（没有 `/etc/default/locale`），
   先放开 `/etc/locale.gen` 再 `locale-gen`。
6. **显示管理器**：GNOME 用 `gdm`（Arch 包名，不是 `gdm3`），自动登录写 `/etc/gdm/custom.conf`；
   KDE 仍然写 `/etc/sddm.conf.d/autologin.conf`。
7. **浏览器**：`firefox` 直接来自 Arch 官方仓库，不需要 Mozilla 的 apt 源与 pin 优先级
   （Ubuntu 的 `firefox`/`chromium-browser` 是 snap 过渡包）。
8. **包构建机制**：9 个「dpkg-deb 打 deb」作业 → **10 个**「ALARM chroot 里 makepkg 打 pacman 包」作业
   （内核按 `prebuilt` / `custom_build` 拆成两个作业 —— Arch 侧即使 prebuilt 也要把 ianchb 的
   Debian 内核 deb 重打包成 pacman 包；`xiaomi-*` 的下载与重打包合并在一个作业里）；
   多出了 `20-alarm-chroot.sh` 与 `21-build-pkg.sh` 两个核心脚本，以及 `22-repack-deb.sh`。
9. **包内服务启用**：Debian 的 `postinst` 里 `systemctl enable` 不移植到 PKGBUILD
   （Arch 惯例是打包不启用服务），统一由 `30-device-packages.sh` 在 chroot 内显式 enable。
10. **同名包替换**：`iio-sensor-proxy` → `iio-sensor-proxy-sheng`（`provides`/`conflicts`），
    并在装包前先移除 ALARM extra 里的 `libssc` / `iio-sensor-proxy`（见上文「换包」一节）。
11. **UCM 软链**：与姊妹仓库一样，`alsa-xiaomi-sheng` 的
    `conf.d/sm8550/Xiaomi-Pad6SPro.conf` 在 Windows 上克隆会退化成普通文件，
    由 PKGBUILD 显式重建软链。
12. **镜像收缩 / depmod / 依赖失败即报错**：这些是姊妹仓库相对上游的新增项，Arch 侧同样保留。

## 已知限制

* **不生成 initramfs**（与上游一致）。因此：
  * 内核模块必须在构建期就 `depmod -a <kver>` 生成索引（`30-device-packages.sh` 已做，
    `90-verify.sh` 硬校验 `modules.dep` / `modules.alias`）；
  * **Plymouth 的 splash 在没有 initramfs 的情况下不会显示**（上游 Debian 版同样如此）。
    我们仍然安装 `plymouth` / `plymouth-themes` 并把 `quiet splash` 写进 cmdline，
    等你哪天用 `mkinitcpio` 自行生成 initramfs（已安装该工具）后即可生效。
* **AUR 主题不编译**：`plymouth-theme-breeze`、`kde-config-plymouth` 只在 AUR，
  构建里不编译 AUR 包（`20-desktop.sh` 会 best-effort 尝试并跳过）。
  需要的话在设备上手动 `paru -S plymouth-theme-breeze`。
* **plasma-mobile 的 SDDM 会话名**：自动登录写的 `Session=plasmamobile` 是按 Plasma 惯例推测的，
  若设备上登录后停留在 SDDM，请在 `/etc/sddm.conf.d/autologin.conf` 里改成该设备实际的会话名。
* **`libssc` 版本回退**：本仓库的 `libssc` 是 0.4.2（带 QRTR 等待补丁），ALARM extra 是 0.4.4。
  构建脚本会强制装本地版本（先 `-Rdd` 移除仓库版本）。若日后 ALARM 的 `libssc` 升级到
  不兼容 ABI，需要同步更新本仓库的 `libssc` PKGBUILD。
* **`active` 分区（A 槽）**保留原 Android/HyperOS 系统，Arch 走 B 槽；
  切换槽位与分区调整请在 TWRP 内完成。
* 项目处于早期阶段，刷写会修改设备分区，请自行备份。

## 需要人工确认的点（构建前请核对）

* `scripts/lists/*.list` 里的包名基于 ALARM 的 `aarch64` 仓库人工核对过一部分
  （`plasma-desktop`、`plasma-nm`、`plasma-mobile`、`gnome-shell`、`gdm`、`plymouth`、
  `protobuf-c`、`libqmi`、`libssc`、`iio-sensor-proxy` 已确认存在）；
  桌面环境安装是 **best-effort**（缺失/改名只警告），核心包由 `90-verify.sh` 硬校验，
  但**其它可选包（字体、`kde-gtk-config` 等）需要跑一次构建确认**。
* `iio-sensor-proxy-sheng` 的 meson 选项名 `-Dsystemdsystemunitdir`、`libssc` 的
  `wait_for_qmi_service.patch` 是否还能干净应用，取决于上游版本（见各自 PKGBUILD 的注释）。
* `firmware-xiaomi-sheng` 声明了 `provides/conflicts/replaces=('linux-firmware')`，
  并且 `30-device-packages.sh` 会在安装前 `pacman -Rdd` 掉全部 `linux-firmware*`
  （元包 + 分包），避免文件路径重叠导致的冲突。需要注意的风险是**反向的**：
  若设备某部分硬件需要 ALARM 固件而 `sheng-firmware` 未覆盖（重点是 Adreno a740 的
  `a740_sqe.fw` / `a740_zap.mbn`，在 ALARM 属 `linux-firmware-qcom`），
  该固件就会缺失 → 首跑后检查 `dmesg | grep -i -E 'firmware|adreno|ath12k'`，
  必要时在设备上单独安装 `linux-firmware-qcom`（确认与本包无路径冲突）。
* **本地包与 ALARM 仓库同名时的版本比较**：`pacman -U` 拒绝「降级」。
  本仓库已处理的同名包是 `libssc`（本地 0.4.2 vs 仓库 0.4.4）——
  `30-device-packages.sh` 先 `pacman -Rdd` 移除仓库版本再装本地包。
  若将来又出现新的同名包，需要照同样方式处理。
* **`kde-gtk-config` / `breeze-icons` / `noto-fonts-cjk` 等可选包**：属于 best-effort
  安装，缺失只警告；KDE/GNOME 的核心包（`plasma-workspace` / `gnome-shell`）
  由 `90-verify.sh` 硬校验。

## 首次推送注意

- 本仓库**未初始化 git**（按需求"先不推送"）。在 Windows 上 `git init && git add` 时，
  脚本的**可执行位不会保留**（Windows 的 git 不跟踪 filemode）。这不影响构建：
  workflow 里每个直接执行的 `./scripts/...` 之前都显式 `chmod +x`，
  镜像内的脚本由 `scripts/host/02-mount-chroot.sh` 统一 `chmod -R 755`。
- `.gitattributes` 设了 `* text=auto eol=lf`，防止 CRLF 破坏 shell 脚本与 PKGBUILD
  （CRLF 会让 `makepkg` 与 `#!/usr/bin/env bash` 直接失败）。
- `.gitignore` 排除了构建产物（`*.deb`、`*.pkg.tar.zst`、`src/`、`pkg/`、`pkgs/`、`deb-out/`、
  `packages/**/sheng-firmware.tar.zst` 等），但 **`packages/*/payload/` 必须提交**
  （那是 alsa UCM2、传感器注册表、systemd unit 的数据源），`patches/`、`mkbootimg`、
  `sm8550.config` 也都要提交。

## 致谢

* **map220v** — TWRP、主线内核移植与大量设备适配
* **alghiffaryfa19** — 上游原始构建脚本
* **ianchb** — [debian-sheng](https://github.com/ianchb/debian-sheng) 与 `xiaomi-*` 设备功能包
* **Dylan Van Assche** — `libssc` 与 `iio-sensor-proxy` 的 SSC 后端
* **Arch Linux ARM** — aarch64 基线 rootfs 与软件包仓库
