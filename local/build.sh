#!/usr/bin/env bash
set -e

#=== 设置自定义参数 ===
echo "===gki内核自定义编译SukiSu Ultra,KernelSU Next脚本"

#下载源码
git clone https://android.googlesource.com/kernel/common -b ${GKI_DEV} --depth=1
cd common
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth=1
git clone https://github.com/KernelSU-Next/kernel_patches.git --depth=1
git clone https://github.com/xiaoxian8/AnyKernel3.git --depth=1
export DEFCONFIG=${PWD}/arch/arm64/configs/gki_defconfig

#=== 是否使用ssg io补丁
if [[ "$APPLY_SSG" = "y" || "$APPLY_SSG" = "y"]; then
  echo ">>>正在添加SSG IO调度"
  git clone https://github.com/xiaoxian8/ssg_patch.git --depth=1
  cp ssg_patch/* ./ -r
  patch -p1 < ssg.patch
else
  echo ">>>跳过SSG IO补丁"
fi

#=== 选择KernelSU分支
if [[ "$SUKUSU" = "Y" || "$SUKISU" = "y"]]; then
  curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
  git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth=1
  patch -p1 < SukiSU_patch/hook/syscall_hooks.patch
  patch -p1 < SukiSU_patch/69_hide_stuff.patch
else
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next
  patch -p1 -F3 < kernel_patches/syscall_hook/min_scope_syscall_hooks_v1.4.patch
  cd KernelSU-Next
  patch -p1 -F3 < ../kernel_patches/susfs/android14-6.1-v1.5.9-ksunext-12823.patch
  cd ..
fi

#=== 是否启用susfs
if [[ "APPLY_SUSFS" = "Y" || "APPLY_SUSFS" = "y"]]; then
  git clone https://gitlab.com/simonpunk/susfs4ksu.git -b ${GKI_VERSION} --depth=1
  cp susfs4ksu/kernel_patches/fs ./ -r
  cp susfs4ksu/kernel_patches/include ./ -r 
  cp susfs4ksu/kernel_patches/50_add_susfs*.patch ./
  patch -p1 < 50_add_susfs*.patch 
else
  
