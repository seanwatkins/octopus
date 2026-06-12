# Building Octopus from Source

This documents the full build process including the cross-compiler setup,
kernel configuration, and initramfs packing. Most of this was worked out
through trial and error on a Ubuntu 24.04 build host.

---

## Build host requirements

```bash
sudo apt-get install -y \
  build-essential git wget cpio unzip rsync bc \
  libncurses-dev libssl-dev python3 python3-pip \
  file bison flex \
  sbcl cl-quicklisp
```

Quicklisp must be installed for the build user:
```bash
sbcl --load /usr/share/common-lisp/source/quicklisp/quicklisp.lisp \
     --eval "(quicklisp-quickstart:install)" \
     --eval "(quit)"
```

---

## Getting Buildroot

```bash
cd /projects
wget https://buildroot.org/downloads/buildroot-2024.11.1.tar.gz
tar xf buildroot-2024.11.1.tar.gz
```

We use Buildroot 2024.11.1. Earlier versions work but 2024.11.x has better
support for the musl libc toolchain we use.

---

## Cross-compiler

Buildroot builds its own cross-compiler as part of the first build. It takes
~20 minutes on first run. The toolchain ends up at:

```
/projects/buildroot-2024.11.1/output/host/bin/x86_64-buildroot-linux-musl-gcc
```

A few issues encountered during toolchain build:

**Kconfig version checks** — the build host's gcc/as/ld version strings
may not match what Buildroot's Kconfig expects. Fix:

```bash
# In buildroot-2024.11.1/
sed -i 's/$(call gcc-version,$(HOSTCC))/0/' \
  support/kconfig/Kconfig.include 2>/dev/null || true
```

**objtool** — requires `libelf-dev` which may not be present. We stub it:

```bash
echo '#!/bin/sh' > /projects/buildroot-2024.11.1/output/build/linux-6.11.11/tools/objtool/objtool
chmod +x /projects/buildroot-2024.11.1/output/build/linux-6.11.11/tools/objtool/objtool
```

---

## Kernel configuration

The kernel config lives at `buildroot/configs/linux.config`. Key things
that were required to get hardware to boot:

**PCI support** — without this the kernel hangs silently at `x86/fpu` on
real hardware. Must be enabled:
```
CONFIG_PCI=y
CONFIG_PCI_DIRECT=y
```

**Retpoline** — caused build failures with our cross-compiler. Disabled:
```
CONFIG_RETPOLINE=n
```

**Network drivers** — we include the common ones:
```
CONFIG_E1000=y      # Intel e1000 (QEMU default)
CONFIG_E1000E=y     # Intel e1000e (common physical NICs)
CONFIG_IGB=y        # Intel i350/i210 (server NICs)
CONFIG_R8169=y      # Realtek (common consumer NICs)
```

To reconfigure the kernel:
```bash
cd /projects/buildroot-2024.11.1
make linux-menuconfig
# Save, then copy back:
cp output/build/linux-6.11.11/.config \
   /share/projects/octopus/buildroot/configs/linux.config
```

---

## The initramfs

We do **not** use Buildroot's built-in initramfs. Instead we maintain a
work tree at `/projects/initrd-work/` and pack it ourselves with a Python
cpio script. This gives us full control over the contents.

### Why not use Buildroot's initramfs?

Buildroot's rootfs packing runs as a non-root user and can't create device
nodes (`/dev/console`, `/dev/null`, `/dev/tty`). The kernel requires these
to exist in the initramfs before PID 1 runs. We prepend them manually.

### The cpio packing script

```python
def pad4(n): return (4 - n % 4) % 4

def cpio_entry(name, mode, rdev=0, data=b''):
    namesize = len(name) + 1
    filesize = len(data)
    hdr = ("070701"
        + "%08X" % 0          # ino
        + "%08X" % mode        # mode
        + "%08X" % 0          # uid
        + "%08X" % 0          # gid
        + "%08X" % 1          # nlink
        + "%08X" % 0          # mtime
        + "%08X" % filesize    # filesize
        + "%08X" % 0          # devmajor
        + "%08X" % 0          # devminor
        + "%08X" % (rdev >> 8) # rdevmajor
        + "%08X" % (rdev & 0xff) # rdevminor
        + "%08X" % namesize    # namesize
        + "%08X" % 0          # check
    ).encode() + name.encode() + b'\x00'
    hdr += b'\x00' * pad4(len(hdr))
    return hdr + (data + b'\x00' * pad4(filesize) if data else b'')

import subprocess, os
os.chdir('/projects/initrd-work')
find = subprocess.run(['find', '.', '-print0'], capture_output=True)
main = subprocess.run(
    ['cpio', '--null', '-o', '-H', 'newc', '--owner', '0:0'],
    input=find.stdout, capture_output=True
).stdout

with open('rootfs-boot.cpio', 'wb') as f:
    # Prepend required device nodes (can't mknod without root)
    f.write(cpio_entry('dev/console', 0o020622, (5 << 8) | 1))
    f.write(cpio_entry('dev/null',    0o020666, (1 << 8) | 3))
    f.write(cpio_entry('dev/tty',     0o020666, (5 << 8) | 0))
    # Main rootfs
    f.write(main)
```

### PID 1

The kernel can only exec an ELF binary as PID 1 — **not a shell script**.
We compile a tiny static C program:

```c
/* init.c — mounts devtmpfs, execs octopus-init */
#include <sys/mount.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

int main(void) {
    mount("devtmpfs", "/dev", "devtmpfs", 0, "mode=0755");
    int fd = open("/dev/console", O_RDWR);
    if (fd >= 0) { dup2(fd,0); dup2(fd,1); dup2(fd,2); if(fd>2) close(fd); }
    char *argv[] = { "/usr/local/bin/octopus-init", NULL };
    char *envp[] = { NULL };
    execve("/usr/local/bin/octopus-init", argv, envp);
    while(1) {}
    return 1;
}
```

Compiled with the Buildroot musl cross-compiler:
```bash
/projects/buildroot-2024.11.1/output/host/bin/x86_64-buildroot-linux-musl-gcc \
  -static -o /projects/initrd-work/init init.c
```

### Dynamic linker issue

Buildroot's musl-based busybox needs `ld-musl-x86_64.so.1` which isn't
included in the Buildroot target by default. Copy from the sysroot:

```bash
cp /projects/buildroot-2024.11.1/output/host/x86_64-buildroot-linux-musl/sysroot/lib/ld-musl-x86_64.so.1 \
   /projects/initrd-work/lib/
```

### glibc for mcp-server binary

The SBCL mcp-server binary is linked against glibc (built on Ubuntu).
These libs must be present in the initramfs:

```bash
mkdir -p /projects/initrd-work/lib/x86_64-linux-gnu
mkdir -p /projects/initrd-work/lib64

cp /lib64/ld-linux-x86-64.so.2          /projects/initrd-work/lib64/
cp /usr/lib/x86_64-linux-gnu/libc.so.6  /projects/initrd-work/lib/x86_64-linux-gnu/
cp /usr/lib/x86_64-linux-gnu/libm.so.6  /projects/initrd-work/lib/x86_64-linux-gnu/
cp /usr/lib/x86_64-linux-gnu/libzstd.so.1 /projects/initrd-work/lib/x86_64-linux-gnu/
cp /usr/lib/x86_64-linux-gnu/libssl.so.3  /projects/initrd-work/lib/x86_64-linux-gnu/
cp /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /projects/initrd-work/lib/x86_64-linux-gnu/

# libc.so is a linker script on the host — use a symlink instead
ln -sf libc.so.6 /projects/initrd-work/lib/x86_64-linux-gnu/libc.so

# Symlink lib64 into usr/lib for linker search path
mkdir -p /projects/initrd-work/usr/lib
for lib in /projects/initrd-work/usr/lib64/*.so*; do
    ln -sf "../lib64/$(basename $lib)" \
       "/projects/initrd-work/usr/lib/$(basename $lib)" 2>/dev/null || true
done
```

---

## Building the SBCL mcp-server binary

The mcp-server binary must be built on a machine with glibc (not musl),
matching the target architecture. We build it on den-a-1 (Ubuntu x86_64):

```bash
cd /opt/mcp_server
sbcl --non-interactive \
     --load ~/.quicklisp/setup.lisp \
     --eval "(ql:quickload '(:hunchentoot :dexador :yason :cl-base64 \
              :ironclad :usocket :bordeaux-threads) :silent t)" \
     --eval "(push \"--save-image\" sb-ext:*posix-argv*)" \
     --load mcp-server.lisp \
     --eval "(sb-ext:save-lisp-and-die \"/tmp/mcp-server\" \
              :toplevel #'main :executable t :compression t)"

cp /tmp/mcp-server /share/projects/octopus/prebuilt/mcp-server
```

**Important:** `mcp-server.lisp` must use `defvar` + `init-config!` (not
`defparameter`) for all configuration variables. `defparameter` evaluates
`uiop:getenv` at image-save time and freezes those values — they won't
reflect the environment on the target machine. The `init-config!` function
is called at the start of `main` and re-reads all env vars fresh.

Also: the file ends with `(main)` which starts the server at load time.
Guard it during image building:
```lisp
(unless (member "--save-image" sb-ext:*posix-argv* :test #'string=)
  (main))
```

---

## Netboot setup

The built kernel and initramfs are served over HTTP. We use nginx in Docker:

```bash
docker run -d \
  --name html-server \
  --restart unless-stopped \
  -p 8080:80 \
  -v /share/html:/usr/share/nginx/html:ro \
  -v /share/projects/octopus/prebuilt:/share/projects/octopus/prebuilt:ro \
  -v /share/html/nginx-octopus.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine
```

`/share/html/octo` is a symlink to `/share/projects/octopus/prebuilt/` so
updating prebuilt files immediately updates what the web server serves.

The nginx config needs `disable_symlinks off` to follow the symlink.

Netboot entry (netboot.xyz custom menu):
```
kernel http://YOUR_SERVER:8080/octo/bzImage-pci ip=dhcp console=tty0 earlyprintk=vga nomodeset panic=5 init=/init
initrd http://YOUR_SERVER:8080/octo/rootfs-boot.cpio
```

---

## QEMU testing

Before booting on real hardware, test with QEMU. Requires a bridge interface
(`br0`) set up via netplan so the VM gets a real DHCP address:

```bash
# /etc/netplan/00-installer-config.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: false
  bridges:
    br0:
      interfaces: [eno1]
      dhcp4: true
      parameters:
        stp: false
        forward-delay: 0
```

Then:
```bash
# Create tap and run QEMU
sudo ip tuntap add dev tap-octopus mode tap user $USER
sudo ip link set tap-octopus master br0
sudo ip link set tap-octopus up

qemu-system-x86_64 \
  -m 4096 \
  -cpu Haswell \
  -kernel /share/html/octo/bzImage-pci \
  -initrd /share/html/octo/rootfs-boot.cpio \
  -append "console=ttyS0,115200 earlyprintk=serial nomodeset panic=5 init=/init" \
  -nographic \
  -serial mon:stdio \
  -netdev tap,id=net0,ifname=tap-octopus,script=no,downscript=no \
  -device e1000,netdev=net0
```

---

## Things that went wrong (and fixes)

| Problem | Cause | Fix |
|---|---|---|
| Kernel hangs at `x86/fpu` | PCI disabled in kernel config | `CONFIG_PCI=y` |
| `Failed to execute /init (error -2)` | Kernel can't exec shell scripts as PID 1 | Static ELF C init binary |
| `Warning: unable to open initial console` | `/dev/console` missing from cpio | Prepend device nodes via Python cpio |
| `SIGILL` on QEMU | CPU emulation too old | Use `-cpu Haswell` |
| `libc.so: invalid ELF header` | Copied linker script instead of real lib | Use symlink `libc.so -> libc.so.6` |
| busybox spinner hangs | `sleep 0.1` not supported by busybox | Use `sleep 1` with iteration count |
| `can't open /dev/tty2` | busybox as PID 1 tries to open VTs | Use our own static ELF init |
| IP shows "no IP assigned" | Banner runs before dhcpcd assigns IP | Start s6 first, then poll for IP |
| cloudflared "not found" | `command -v` fails without PATH | Use full path `/usr/local/bin/cloudflared` |
| mcp-server shows wrong URL | `defparameter` freezes env at image-save | Use `defvar` + `init-config!` |
| Token invalid | Missing leading `e` from `eyJh...` | Check token starts with `eyJ` |
