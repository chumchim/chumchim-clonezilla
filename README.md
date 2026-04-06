# School Clonezilla

Custom Clonezilla for school PC deployment.
Boot from USB → [1] Capture or [2] Deploy → Done!

Based on [Clonezilla](https://clonezilla.org/) (GPL open source).


## Goal

Make PC cloning so easy that any teacher can do it:
- Boot USB
- Select [1] or [2]
- Wait
- Done

No Sysprep, no PowerShell, no commands to type.


## Features (Planned)

- [x] Simple menu: Capture / Deploy
- [ ] Thai + English interface
- [ ] Auto-detect disks
- [ ] Progress bar
- [ ] Built-in Windows debloat (optional)
- [ ] UEFI + Legacy support
- [ ] Custom branding


## Development Plan

### Phase 1: Build custom Clonezilla ISO
- Download Clonezilla Live
- Remaster ISO with custom scripts
- Test boot in VM

### Phase 2: Simplify menu
- Remove all options except Capture/Deploy
- Auto-detect source/target disks
- Clear progress display

### Phase 3: Thai language
- Translate menu to Thai
- Bilingual support

### Phase 4: Extra features
- Windows debloat after deploy
- Network deploy support
- Multiple image management

### Phase 5: Testing
- Test on school hardware
- Different PC brands
- UEFI + Legacy


## Tech Stack

- Clonezilla Live (Debian-based)
- Partclone (clone engine)
- Bash scripting
- Dialog/Whiptail (TUI)


## Build

```bash
# TODO: Build instructions
```


## License

GPL v2 (same as Clonezilla)
