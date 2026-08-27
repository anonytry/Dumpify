# missi-user 15 AQ3A.240912.001 OS2.0.210.0.VMWMIXM release-keys
- manufacturer: xiaomi
- platform: parrot
- codename: river
- flavor: missi-user
- release: 15
- id: AQ3A.240912.001
- incremental: OS2.0.210.0.VMWMIXM
- tags: release-keys
- fingerprint: Redmi//river:14/UKQ1.231003.002/OS2.0.210.0.VMWMIXM:user/release-keys
- is_ab: true
- brand: Redmi
- branch: missi-user-15-AQ3A.240912.001-OS2.0.210.0.VMWMIXM-release-keys

## Decompressing Large Files
Files over 97MB are compressed with zstd.
```bash
# Install zstd
sudo apt install zstd      # Debian/Ubuntu
sudo pacman -S zstd        # Arch
pkg install zstd            # Termux

# Single file
zstd -d filename.zst --rm

# All .zst files
find . -name '*.zst' -exec sh -c 'zstd -d "$1" --rm' _ {} \;
```
