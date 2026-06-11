cmake_minimum_required(VERSION 3.24)

# NONE: no compiler needed at the envelope level; each subproject
# configures its own toolchain via execute_process below.
project(VesperaWorkspace NONE)

# ────────────────────────────────────────────────────────────────
# Options
# ────────────────────────────────────────────────────────────────

set(VESPERA_COMPILER "clang" CACHE STRING "Kernel compiler: clang or gcc")
set_property(CACHE VESPERA_COMPILER PROPERTY STRINGS clang gcc)

# ────────────────────────────────────────────────────────────────
# Paths
# ────────────────────────────────────────────────────────────────
set(ENV_DIR         "${CMAKE_CURRENT_SOURCE_DIR}")
set(OS_SOURCE_DIR   "${ENV_DIR}/VesperaOS")
set(APPS_SOURCE_DIR "${ENV_DIR}/VesperaApps")
set(SCRIPTS_DIR     "${ENV_DIR}/scripts")
set(OVMF_DIR        "${ENV_DIR}/OVMF")

# Sub-build dirs live inside the umbrella build tree so a single
# `rm -rf cmake-build-debug/` wipes everything.
set(OS_BUILD_DIR   "${CMAKE_CURRENT_BINARY_DIR}/VesperaOS")
set(APPS_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/VesperaApps")

# The boot image is produced into the umbrella build dir.
set(BOOT_IMG "${CMAKE_CURRENT_BINARY_DIR}/boot.img")

# Sysroot — same resolution as the sub-projects.
if(NOT DEFINED VESPERA_SYSROOT)
    if(DEFINED ENV{VESPERA_SYSROOT})
        set(VESPERA_SYSROOT "$ENV{VESPERA_SYSROOT}")
    else()
        set(VESPERA_SYSROOT "${ENV_DIR}/VesperaSysroot")
    endif()
endif()
get_filename_component(VESPERA_SYSROOT "${VESPERA_SYSROOT}" ABSOLUTE)

message(STATUS "")
message(STATUS "═══════════════════════════════════════════")
message(STATUS "  VesperaWorkspace")
message(STATUS "  Compiler : ${VESPERA_COMPILER}")
message(STATUS "  Sysroot  : ${VESPERA_SYSROOT}")
message(STATUS "  OS build : ${OS_BUILD_DIR}")
message(STATUS "  App build: ${APPS_BUILD_DIR}")
message(STATUS "═══════════════════════════════════════════")
message(STATUS "")

# Guard: submodules must be initialised.
if(NOT EXISTS "${OS_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
            "VesperaOS source not found at ${OS_SOURCE_DIR}.\n"
            "Run: git submodule update --init --recursive")
endif()
if(NOT EXISTS "${APPS_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
            "VesperaApps source not found at ${APPS_SOURCE_DIR}.\n"
            "Run: git submodule update --init --recursive")
endif()

# ────────────────────────────────────────────────────────────────
# Kernel compiler flags  (logic from configure.sh, now in CMake)
# ────────────────────────────────────────────────────────────────
if(VESPERA_COMPILER STREQUAL "clang")
    set(_KC  clang)
    set(_KCX clang++)
    set(_KCXX_FLAGS
            "--target=x86_64-elf -ffreestanding -nostdinc \
         -fno-stack-protector -fno-omit-frame-pointer -mno-red-zone \
         -fshort-wchar -fno-exceptions -fno-rtti \
         -g -O0 -fno-inline -Wall -mcmodel=kernel -fno-pic -fno-pie")
    set(_KC_FLAGS
            "--target=x86_64-elf -ffreestanding -nostdinc \
         -fno-stack-protector -mno-red-zone -fno-pic -fno-pie \
         -mcmodel=kernel -O2")
    set(_KLD_FLAGS "-fuse-ld=lld")
    set(_KLD_EXTRA -DCMAKE_LINKER=ld.lld)
elseif(VESPERA_COMPILER STREQUAL "gcc")
    set(_KC  gcc)
    set(_KCX g++)
    set(_KCXX_FLAGS
            "-ffreestanding -nostdinc \
         -fno-stack-protector -fno-omit-frame-pointer -mno-red-zone \
         -fshort-wchar -fno-exceptions -fno-rtti \
         -g -O0 -fno-inline -Wall -mcmodel=kernel -fno-pic -fno-pie")
    set(_KC_FLAGS
            "-ffreestanding -nostdinc \
         -fno-stack-protector -mno-red-zone -fno-pic -fno-pie \
         -mcmodel=kernel -O2")
    set(_KLD_FLAGS "-fuse-ld=bfd")
    set(_KLD_EXTRA "")
else()
    message(FATAL_ERROR "VESPERA_COMPILER must be 'clang' or 'gcc', got '${VESPERA_COMPILER}'")
endif()

# ────────────────────────────────────────────────────────────────
# Configure subprojects at cmake-configure time
# This replaces the need to run configure.sh manually.
# Re-runs when CMake re-configures (e.g., after option change).
# ────────────────────────────────────────────────────────────────
message(STATUS "[VesperaWorkspace] Configuring VesperaOS (${VESPERA_COMPILER})...")
execute_process(
        COMMAND ${CMAKE_COMMAND}
        -S "${OS_SOURCE_DIR}"
        -B "${OS_BUILD_DIR}"
        -G "${CMAKE_GENERATOR}"
        -DCMAKE_C_COMPILER=${_KC}
        -DCMAKE_CXX_COMPILER=${_KCX}
        -DCMAKE_C_COMPILER_WORKS=TRUE
        -DCMAKE_CXX_COMPILER_WORKS=TRUE
        -DCMAKE_CXX_FLAGS=${_KCXX_FLAGS}
        -DCMAKE_C_FLAGS=${_KC_FLAGS}
        -DCMAKE_EXE_LINKER_FLAGS=${_KLD_FLAGS}
        ${_KLD_EXTRA}
        -DVESPERA_SYSROOT=${VESPERA_SYSROOT}
        RESULT_VARIABLE _os_cfg_result
)
if(_os_cfg_result)
    message(FATAL_ERROR "VesperaOS cmake configuration failed (exit ${_os_cfg_result})")
endif()

message(STATUS "[VesperaWorkspace] Configuring VesperaApps...")
execute_process(
        COMMAND ${CMAKE_COMMAND}
        -S "${APPS_SOURCE_DIR}"
        -B "${APPS_BUILD_DIR}"
        -G "${CMAKE_GENERATOR}"
        -DCMAKE_C_COMPILER=${_KC}
        -DCMAKE_CXX_COMPILER=${_KCX}
        -DCMAKE_C_COMPILER_WORKS=TRUE
        -DCMAKE_CXX_COMPILER_WORKS=TRUE
        -DVESPERA_SYSROOT=${VESPERA_SYSROOT}
        RESULT_VARIABLE _apps_cfg_result
)
if(_apps_cfg_result)
    message(FATAL_ERROR "VesperaApps cmake configuration failed (exit ${_apps_cfg_result})")
endif()

# ────────────────────────────────────────────────────────────────
# Test build (mirrors configure.sh's cmake-build-tests)
# cmake -S VesperaWorkspace -B build -DVESPERA_BUILD_TESTS=ON
# ────────────────────────────────────────────────────────────────
option(VESPERA_BUILD_TESTS "Configure the VesperaOS test build" OFF)
set(TESTS_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/VesperaOS-tests")

if(VESPERA_BUILD_TESTS)
    message(STATUS "[VesperaWorkspace] Configuring VesperaOS tests...")
    execute_process(
            COMMAND ${CMAKE_COMMAND}
            -S "${OS_SOURCE_DIR}"
            -B "${TESTS_BUILD_DIR}"
            -DCMAKE_BUILD_TYPE=Debug
            -DVESPERA_BUILD_TESTS=ON
            RESULT_VARIABLE _tests_cfg_result
    )
    if(_tests_cfg_result)
        message(FATAL_ERROR "VesperaOS test configuration failed (exit ${_tests_cfg_result})")
    endif()
endif()

# ────────────────────────────────────────────────────────────────
# Parallel job count
# ────────────────────────────────────────────────────────────────
include(ProcessorCount)
ProcessorCount(NPROC)
if(NPROC EQUAL 0)
    set(NPROC 4)
endif()

# Convenience shorthands for cmake --build invocations.
set(_build_os   ${CMAKE_COMMAND} --build ${OS_BUILD_DIR}   --parallel ${NPROC})
set(_build_apps ${CMAKE_COMMAND} --build ${APPS_BUILD_DIR} --parallel ${NPROC})

# Derived paths used in multiple targets.
set(LIMINE_DIR  "${OS_SOURCE_DIR}/limine")
set(KERNEL_ELF  "${OS_BUILD_DIR}/kernel/kernel.elf")

# ════════════════════════════════════════════════════════════════
# Build targets
# ════════════════════════════════════════════════════════════════

# ── Kernel ──────────────────────────────────────────────────────
add_custom_target(build-kernel
        COMMAND ${_build_os} --target os-build-kernel
        COMMENT "Building kernel.elf"
)

# ── Userspace libraries (vesplib, stella, lvgl, lua, …) ─────────
add_custom_target(build-libs
        COMMAND ${_build_os} --target sysroot_install
        COMMENT "Building userspace libraries → sysroot"
)

# ── Applications (VesperaApps → sysroot/bin) ────────────────────
add_custom_target(build-apps
        COMMAND ${_build_apps} --target install_apps
        COMMENT "Building VesperaApps → sysroot/bin"
)

# ── Full build: kernel + libs + apps  (no disk image) ───────────
add_custom_target(build
        COMMAND ${_build_os}   --target os-build-kernel
        COMMAND ${_build_os}   --target sysroot_install
        COMMAND ${_build_apps} --target install_apps
        COMMENT "Full build: kernel + libs + apps (no disk image)"
)

# ════════════════════════════════════════════════════════════════
# Disk image targets
# ════════════════════════════════════════════════════════════════

# pack — create disk image from already-populated sysroot (fast).
#   Assumes kernel, libs, and apps are already built.
add_custom_target(pack
        COMMAND bash ${SCRIPTS_DIR}/make_disk.sh
        ${BOOT_IMG}
        ${LIMINE_DIR}
        ${KERNEL_ELF}
        ${OS_SOURCE_DIR}
        ${VESPERA_SYSROOT}
        WORKING_DIRECTORY ${ENV_DIR}
        COMMENT "Packing disk image from existing build (no rebuild)"
)

# disk-image — full pipeline: build everything, then pack.
add_custom_target(disk-image
        COMMAND ${_build_os}   --target os-build-kernel
        COMMAND ${_build_os}   --target sysroot_install
        COMMAND ${_build_apps} --target install_apps
        COMMAND bash ${SCRIPTS_DIR}/make_disk.sh
        ${BOOT_IMG}
        ${LIMINE_DIR}
        ${KERNEL_ELF}
        ${OS_SOURCE_DIR}
        ${VESPERA_SYSROOT}
        WORKING_DIRECTORY ${ENV_DIR}
        COMMENT "Full disk image: kernel + libs + apps + pack"
)

# ════════════════════════════════════════════════════════════════
# Incremental update targets (fast iteration)
# Both require an initial boot.img — run pack/disk-image first.
# ════════════════════════════════════════════════════════════════

# update-kernel — rebuild kernel, splice into EFI partition.
add_custom_target(update-kernel
        COMMAND ${_build_os} --target os-build-kernel
        COMMAND bash ${SCRIPTS_DIR}/update_kernel.sh
        ${BOOT_IMG}
        ${KERNEL_ELF}
        COMMENT "Rebuilding kernel → splicing into EFI partition"
)

# update-rootfs — rebuild apps, rsync into rootfs partition.
add_custom_target(update-rootfs
        COMMAND ${_build_apps} --target install_apps
        COMMAND bash ${SCRIPTS_DIR}/update_rootfs.sh
        ${BOOT_IMG}
        ${VESPERA_SYSROOT}
        ${OS_SOURCE_DIR}
        COMMENT "Rebuilding apps → rsyncing into rootfs partition"
)

# ════════════════════════════════════════════════════════════════
# QEMU targets
# ════════════════════════════════════════════════════════════════

set(TEST_DISK_IMG ${CMAKE_CURRENT_BINARY_DIR}/disk.img)

add_custom_command(
        OUTPUT ${TEST_DISK_IMG}
        COMMAND bash ${SCRIPTS_DIR}/make_test_disk.sh ${TEST_DISK_IMG}
        DEPENDS ${SCRIPTS_DIR}/make_test_disk.sh
        COMMENT "Creating test disk image"
)
add_custom_target(test_disk_image DEPENDS ${TEST_DISK_IMG})

# Common QEMU flags shared by run / run-full / run-quick.
set(_QEMU
        qemu-system-x86_64
        -m 4G
        -smp 8
        -machine q35
        -enable-kvm
        -cpu host
        -vga std
        -drive if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_DIR}/OVMF_CODE-pure-efi.fd
        -drive if=pflash,format=raw,unit=1,file=${CMAKE_CURRENT_BINARY_DIR}/OVMF_VARS.fd
        -net none
        -monitor stdio
        -device qemu-xhci,id=xhci1
        -drive id=usbstick,file=${BOOT_IMG},if=none,format=raw
        -drive id=fat32drive,file=${TEST_DISK_IMG},if=none,format=raw
        -device usb-storage,drive=usbstick
        -device nvme,id=nvme0,serial=deadbeef
        -device nvme-ns,drive=fat32drive,bus=nvme0
        -device usb-kbd
        -trace *msi*
        -D ${CMAKE_CURRENT_BINARY_DIR}/qemu.log
        -no-reboot
        -no-shutdown
)

# Copy the mutable VARS file before every QEMU launch so firmware
# variable changes from one run do not bleed into the next.
set(_OVMF_VARS_COPY
        ${CMAKE_COMMAND} -E copy
        ${OVMF_DIR}/OVMF_VARS-pure-efi.fd
        ${CMAKE_CURRENT_BINARY_DIR}/OVMF_VARS.fd
)

# run — launch QEMU with existing disk image (no rebuild).
add_custom_target(run
        DEPENDS test_disk_image
        COMMAND ${_OVMF_VARS_COPY}
        COMMAND ${_QEMU}
        COMMENT "Launching QEMU (no rebuild)"
)

# run-quick — rebuild apps + update rootfs + run.  Typical dev loop.
add_custom_target(run-quick
        DEPENDS test_disk_image
        COMMAND ${_build_apps} --target install_apps
        COMMAND bash ${SCRIPTS_DIR}/update_rootfs.sh
        ${BOOT_IMG}
        ${VESPERA_SYSROOT}
        ${OS_SOURCE_DIR}
        COMMAND ${_OVMF_VARS_COPY}
        COMMAND ${_QEMU}
        COMMENT "Rebuild apps → update rootfs → run"
)

# run-full — full rebuild + pack + run.
add_custom_target(run-full
        DEPENDS test_disk_image
        COMMAND ${_build_os}   --target build-kernel
        COMMAND ${_build_os}   --target sysroot_install
        COMMAND ${_build_apps} --target install_apps
        COMMAND bash ${SCRIPTS_DIR}/make_disk.sh
        ${BOOT_IMG}
        ${LIMINE_DIR}
        ${KERNEL_ELF}
        ${OS_SOURCE_DIR}
        ${VESPERA_SYSROOT}
        COMMAND ${_OVMF_VARS_COPY}
        COMMAND ${_QEMU}
        WORKING_DIRECTORY ${ENV_DIR}
        COMMENT "Full rebuild → pack → run"
)

# run-debug — GDB stub on :1234, halted at entry.
#   Connect with: gdb kernel.elf -ex 'target remote :1234'
add_custom_target(run-debug
        DEPENDS test_disk_image
        COMMAND qemu-system-x86_64
        -m 4G
        -smp 8
        -machine q35
        -enable-kvm
        -cpu host
        -drive if=pflash,format=raw,unit=0,file=${OVMF_DIR}/OVMF.fd
        -net none
        -monitor stdio
        -device qemu-xhci,id=xhci1
        -device qemu-xhci,id=xhci2
        -drive id=usbstick,file=${BOOT_IMG},if=none,format=raw
        -drive id=fat32drive,file=${TEST_DISK_IMG},if=none,format=raw
        -device usb-storage,drive=usbstick
        -device usb-storage,drive=fat32drive
        -trace *xhci*
        -D ${CMAKE_CURRENT_BINARY_DIR}/qemu.log
        -no-reboot
        -no-shutdown
        -s -S
        COMMENT "QEMU + GDB stub on :1234"
)

# ════════════════════════════════════════════════════════════════
# Flash
# ════════════════════════════════════════════════════════════════
if(DEFINED DEVICE)
    add_custom_target(flash
            COMMAND ${CMAKE_COMMAND} -E echo "Writing to ${DEVICE}..."
            COMMAND sudo dd if=${BOOT_IMG} of=${DEVICE}
            bs=4M status=progress conv=fsync
            COMMENT "Flashing boot.img to ${DEVICE}"
    )
else()
    add_custom_target(flash
            COMMAND bash ${SCRIPTS_DIR}/flash.sh ${BOOT_IMG}
            COMMENT "Launching interactive USB flash tool"
    )
endif()

# ════════════════════════════════════════════════════════════════
# Clean
# ════════════════════════════════════════════════════════════════
add_custom_target(clean-all
        COMMAND ${CMAKE_COMMAND} -E rm -rf
        ${CMAKE_CURRENT_BINARY_DIR}/boot.img
        ${OS_BUILD_DIR}
        ${APPS_BUILD_DIR}
        ${TESTS_BUILD_DIR}
        ${VESPERA_SYSROOT}
        COMMENT "Removing all build artifacts and sysroot"
)

# ════════════════════════════════════════════════════════════════
# Tests (only available when VESPERA_BUILD_TESTS=ON)
# ════════════════════════════════════════════════════════════════
if(VESPERA_BUILD_TESTS)
    add_custom_target(test
            COMMAND ${CMAKE_COMMAND} --build ${TESTS_BUILD_DIR} --parallel ${NPROC}
            COMMAND ${CMAKE_CTEST_COMMAND} --test-dir ${TESTS_BUILD_DIR} --output-on-failure
            COMMENT "Building and running VesperaOS unit tests"
    )
endif()

# ════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════
message(STATUS "")
message(STATUS "Available targets:")
message(STATUS "  build-kernel    kernel.elf only")
message(STATUS "  build-libs      vesplib / stella / lvgl / lua → sysroot")
message(STATUS "  build-apps      VesperaApps → sysroot/bin")
message(STATUS "  build           kernel + libs + apps (no disk)")
message(STATUS "  ─────────────────────────────────────────────────────")
message(STATUS "  pack            disk image from existing build (fast)")
message(STATUS "  disk-image      full build + pack")
message(STATUS "  ─────────────────────────────────────────────────────")
message(STATUS "  update-kernel   rebuild kernel → splice EFI  (fast)")
message(STATUS "  update-rootfs   rebuild apps   → rsync rootfs (fast)")
message(STATUS "  ─────────────────────────────────────────────────────")
message(STATUS "  run             QEMU with existing image (no rebuild)")
message(STATUS "  run-quick       rebuild apps + rootfs → run")
message(STATUS "  run-full        full rebuild + pack → run")
message(STATUS "  run-debug       QEMU + GDB stub on :1234")
message(STATUS "  flash           write boot.img to USB")
message(STATUS "  clean-all       rm build/ + sysroot/")
if(VESPERA_BUILD_TESTS)
    message(STATUS "  test            build + run unit tests")
endif()
message(STATUS "")
message(STATUS "Reconfigure options:")
message(STATUS "  -DVESPERA_COMPILER=gcc        switch to GCC kernel build")
message(STATUS "  -DVESPERA_BUILD_TESTS=ON      include test build")
message(STATUS "  -DVESPERA_SYSROOT=/path/...   custom sysroot location")
message(STATUS "")


add_subdirectory(VesperaOS)
add_subdirectory(VesperaApps)