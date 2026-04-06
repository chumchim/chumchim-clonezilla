# ChumChim-Clonezilla

Custom Clonezilla for easy PC cloning.
Boot from USB → Clone or Install → Done!

Based on [Clonezilla](https://clonezilla.org/) (GPL v2 open source).


## What it does

```
Clone:    Copy a PC to an image file
Install:  Install image file to another PC

One USB does everything.
```


## How to use

### Make USB (once)
1. Download `chumchim-clonezilla.iso`
2. Use [Rufus](https://rufus.ie) to write ISO to USB
3. Done!

### Clone a PC
1. Install Windows + software on one PC (normally)
2. Shut down
3. Plug USB → Boot (F12) → Select **[1] Clone Image this PC**
4. Follow prompts → Wait 10-30 min → Image saved!

### Install to other PCs
1. Plug USB → Boot (F12) → Select **[2] Install Image to PC**
2. Select image → Select disk → Wait 10-30 min
3. Remove USB → Reboot → PC ready with all software!


## Features

- Simple menu: Clone / Install
- No Sysprep needed
- No commands to type
- UEFI + Legacy boot
- Based on Clonezilla (stable, tested 15+ years)


## Build from source

Requires WSL (Ubuntu):

```bash
wsl -d Ubuntu -u root -- bash build/build-in-wsl.sh
```

Output: `C:\Images\chumchim-clonezilla.iso`


## License

GPL v2 (same as Clonezilla)


## Credits

- [Clonezilla](https://clonezilla.org/) by Steven Shiau
- ChumChim-Clonezilla by [@chumchim](https://github.com/chumchim)
