#!/usr/bin/bash
set -e

#=== 安装依赖 ===
sudo apt-get install curl bison flex make binutils dwarves git pahole zip perl make gcc python3 python-is-python3 bc libssl-dev libelf-dev -y

#下载LLVM以及设置环境变量
wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-Linux-X64.tar.xz
tar -Jxf LLVM-20.1.8-Linux-X64.tar.xz
export PATH=$PWD/LLVM-20.1.8-Linux-X64/bin:$PATH
#=== 设置自定义参数 ===
echo "===gki内核自定义编译SukiSu Ultra,KernelSU Next脚本"

#=== 下载源码 ===
git clone https://android.googlesource.com/kernel/common -b ${GKI_DEV} --depth=1
cd common
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth=1
git clone https://github.com/KernelSU-Next/kernel_patches.git --depth=1
git clone https://github.com/xiaoxian8/AnyKernel3.git --depth=1
export DEFCONFIG_FILE=${PWD}/arch/arm64/configs/gki_defconfig
GKI_VERSION="gki-$(echo $GKI_DEV | cut -d'-' -f1-2)"

#=== 清除abi文件
rm -rf common/android/abi_gki_protected_exports_* || true
sed -i 's/ -dirty//g' scripts/setlocalversion

#=== 启用LTO优化 ===
cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG_THIN=y
CONFIG_HAS_LTO_CLANG=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO=y
CONFIG_KSU_MANUAL_HOOK=y
EOF

#=== 是否使用ssg io补丁
if [[ "$APPLY_SSG" == "Y" || "$APPLY_SSG" == "y" ]]; then
  echo ">>>正在添加SSG IO调度"
  git clone https://github.com/xiaoxian8/ssg_patch.git --depth=1
  cp ssg_patch/* ./ -r
  patch -p1 < ssg.patch
  echo "CONFIG_MQ_IOSCHED_SSG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y" >> "$DEFCONFIG_FILE"
else
  echo ">>>跳过SSG IO补丁"
fi

#=== 选择KernelSU分支
if [[ "$SUKISU" == "SukiSU Ultra" ]]; then
  curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
  patch -p1 < SukiSU_patch/hooks/syscall_hooks.patch
  patch -p1 < SukiSU_patch/69_hide_stuff.patch
else
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next
  patch -p1 -F3 < kernel_patches/syscall_hook/min_scope_syscall_hooks_v1.4.patch
  cd KernelSU-Next
  patch -p1 -F3 < ../kernel_patches/susfs/android14-6.1-v1.5.9-ksunext-12823.patch
  cd ..
fi

#=== 是否启用susfs
if [[ "$APPLY_SUSFS" == "Y" || "$APPLY_SUSFS" == "y" ]]; then
  echo ">>> 正在启用susfs"
  git clone https://gitlab.com/simonpunk/susfs4ksu.git -b ${GKI_VERSION} --depth=1
  cp susfs4ksu/kernel_patches/fs ./ -r
  cp susfs4ksu/kernel_patches/include ./ -r 
  cp susfs4ksu/kernel_patches/50_add_susfs*.patch ./
  patch -p1 < 50_add_susfs*.patch
  cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
#CONFIG_KSU_SUSFS_SUS_OVERLAYFS is not set
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
EOF
else
  cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_KSU_SUSFS=n
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=n
CONFIG_KSU_SUSFS_SUS_PATH=n
CONFIG_KSU_SUSFS_SUS_MOUNT=b
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=n
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=n
CONFIG_KSU_SUSFS_SUS_KSTAT=n
#CONFIG_KSU_SUSFS_SUS_OVERLAYFS is not set
CONFIG_KSU_SUSFS_TRY_UMOUNT=n
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=n
CONFIG_KSU_SUSFS_SPOOF_UNAME=n
CONFIG_KSU_SUSFS_ENABLE_LOG=n
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=n
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=n
CONFIG_KSU_SUSFS_OPEN_REDIRECT=n
EOF
fi

#=== 是否启用KPM
if [[ "$APPLY_KPM" == "Y" || "$APPLY_KPM" == "y" ]]; then
  echo "CONFIG_KPM=y" >> $DEFCONFIG_FILE
fi

# ===== 启用网络功能增强优化配置 =====
if [[ "$APPLY_BETTERNET" == "y" || "$APPLY_BETTERNET" == "Y" ]]; then
  echo ">>> 正在启用网络功能增强优化配置..."
  echo "CONFIG_BPF_STREAM_PARSER=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_MAX=65534" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_PORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMARK=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTIP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_MAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETIFACE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_LIST_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_NAT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >> "$DEFCONFIG_FILE"
fi

# ===== 添加 BBR 等一系列拥塞控制算法 =====
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" || "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
  echo ">>> 正在添加 BBR 等一系列拥塞控制算法..."
  echo "CONFIG_TCP_CONG_ADVANCED=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BBR=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_CUBIC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_VEGAS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_NV=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_WESTWOOD=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_HTCP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BRUTAL=y" >> "$DEFCONFIG_FILE"
  if [[ "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
    echo "CONFIG_DEFAULT_TCP_CONG=bbr" >> "$DEFCONFIG_FILE"
  else
    echo "CONFIG_DEFAULT_TCP_CONG=cubic" >> "$DEFCONFIG_FILE"
  fi
fi

#编译参数
args=(-j$(nproc --all) O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 DEPMOD=depmod DTC=dtc)
make ${args[@]} gki_defconfig
make ${args[@]} Image.lz4 modules
make ${args[@]} INSTALL_MOD_PATH=modules modules_install

#打包内核
if [[ "$APPLY_KPM" == "Y" || "$APPLY_KPM" == "y" ]]; then
  
  chmod +x SukiSU_patch/kpm/patch_linux
  cp $(find out -type f  -name "Image") ./
  SukiSU_patch/kpm/patch_linux
  mv oImage AnyKernel3/Image
  cd AnyKernel3
  zip -r9v ../out/kernel.zip *
else
 cp $(find out -type f  -name "Image") ./AnyKernel3
 cd AnyKernel3
 zip -r9v ../out/kernel.zip *
