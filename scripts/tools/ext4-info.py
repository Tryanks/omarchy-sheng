#!/usr/bin/env python3
"""打印 ext4 镜像的几何信息，并检查「文件是否比文件系统短」（截断 bug）。

用法: python3 scripts/tools/ext4-info.py <rootfs.img>

为什么需要它：我们把 10G 镜像用 `resize2fs -M` 缩小后再 truncate 到
「块数 × 块大小」。如果这一步算错，产出的镜像会比文件系统本身短 —— 内核挂载时
读尾部会失败（设备侧表现为刷入后黑屏）。这里在 CI 里直接判死。
"""
import os
import struct
import sys

SUPERBLOCK_OFFSET = 1024

INCOMPAT = [
    (0x0001, 'COMPRESSION'), (0x0002, 'FILETYPE'), (0x0004, 'RECOVER'),
    (0x0008, 'JOURNAL_DEV'), (0x0010, 'META_BG'), (0x0040, 'EXTENTS'),
    (0x0080, '64BIT'), (0x0100, 'MMP'), (0x0200, 'FLEX_BG'),
    (0x0400, 'EA_INODE'), (0x1000, 'DIRDATA'), (0x2000, 'CSUM_SEED'),
    (0x4000, 'LARGEDIR'), (0x8000, 'INLINE_DATA'), (0x10000, 'ENCRYPT'),
    (0x20000, 'CASEFOLD'), (0x100000, 'ORPHAN_FILE'),
]


def main(path: str) -> int:
    file_size = os.path.getsize(path)
    with open(path, 'rb') as f:
        f.seek(SUPERBLOCK_OFFSET)
        sb = f.read(1024)

    magic, = struct.unpack_from('<H', sb, 0x38)
    if magic != 0xEF53:
        print(f'!! 不是 ext4 超级块（magic=0x{magic:04x}）—— 镜像可能损坏')
        return 1

    blocks_lo, = struct.unpack_from('<I', sb, 0x04)
    blocks_hi, = struct.unpack_from('<I', sb, 0x150)
    log_block_size, = struct.unpack_from('<I', sb, 0x18)
    feat_incompat, = struct.unpack_from('<I', sb, 0x60)
    state, = struct.unpack_from('<H', sb, 0x3A)
    lastcheck, = struct.unpack_from('<I', sb, 0x40)

    blocks = blocks_lo | (blocks_hi << 32)
    block_size = 1024 << log_block_size
    fs_size = blocks * block_size

    print(f'ext4 块大小       : {block_size}')
    print(f'ext4 块数         : {blocks}')
    print(f'ext4 文件系统大小 : {fs_size} ({fs_size / 1048576:.1f} MiB)')
    print(f'镜像文件大小      : {file_size} ({file_size / 1048576:.1f} MiB)')
    print(f'文件系统状态      : {"clean" if state == 1 else f"0x{state:x}（非 clean，可能需要 fsck）"}')
    print(f'最后检查时间      : {lastcheck}')
    print('incompat 特性     : ' + (', '.join(n for b, n in INCOMPAT if feat_incompat & b) or '（无）'))

    rc = 0
    if file_size < fs_size:
        print(f'!! FAIL: 镜像文件比文件系统短 {fs_size - file_size} 字节 '
              f'（{100 * file_size / fs_size:.2f}%）—— 内核读尾部会失败，设备侧表现为黑屏')
        rc = 1
    else:
        print('OK: 文件不小于文件系统（没有被截断）')
    if not feat_incompat & 0x0040:
        print('!! WARN: 未启用 EXTENTS 特性，不是常规 mkfs.ext4 产物')
    return rc


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
