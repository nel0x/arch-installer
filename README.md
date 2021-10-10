# Arch Installer
Custom Arch Installation and Config Script

## Obtaining The Repository
- Update mirrorlist and install git: `pacman -Sy git`
- Get the script: `git clone https://gitlab.com/Nelox/arch-installer`
______________________________________________________________________________

## How to use

### For single-boot
```
cd arch-installer
chmod +x archmatic.sh
./archmatic.sh
```

### For dual-boot
```
cd arch-installer
chmod +x archmatic-dualboot.sh
```
- Create a boot and a lvm partition.
- Enter both and your esp under the `EDIT: Set partitions (manually)`-section into the script.
```
./archmatic-dualboot.sh
```
______________________________________________________________________________
## Don't just run this script. Examine it. Customize it. Create your own version.
______________________________________________________________________________

## Troubleshooting Arch Linux

[Arch Linux Installation Guide](https://gitlab.com/Nelox/encrypted-arch-installation)
______________________________________________________________________________

## License :scroll:

This project is licenced under the GNU General Public License V3. For more information, visit https://www.gnu.org/licenses/gpl-3.0.en.html
