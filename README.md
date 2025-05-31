# update_yo_shiz

## Description

This tool provides automation for all update steps on Arch Linux, specific to my own systems.

This means in addition to `pacman`, it also runs `aura` which is my preferred AUR manager.

If you want it to run for your AUR manager, feel free to create an issue.

Features:
- Handles all the standard `pacman` steps, including rebooting, and checking the log for errors.
- Has option to only list updates, including AUR ones.
- Has option to only clean the package file cache, including configured ones for AUR or otherwise.
- Has option to only check the system log for errors.
- Can be configured to uninstall/reinstall odd AUR packages that break dependencies with non-AUR packages during updates (e.g. the `virtualbox-ext-oracle` AUR package which breaks updating `virtualbox` and vice versa).

## Usage

```
Name:
  UpdateYoShiz

Message:
  Online help.

Description:
  Automates all the steps normally taken to update Danamis machines:
     1. Check pacman updates.
     2. Uninstall conflicting AUR packages if needed.
     3. Download pacman updates.
     4. Apply pacman downloaded updates. Warn to close all apps first.
     5. Check for new *.pacnew files.
     6. Reboot if needed.
     7. Check system log for (new) error messages, if rebooted.
     8. Check+apply pacman updates.
     9. Check+apply aura updates.
    10. Goto 8 until updates are clear.
    11. Reinstall conflicting AUR packages if needed.
    12. Clear package caches.

Usage:
  uys [-bcp] [b|boot_log] [c|check] [p|pcc]
  uys [-r|r|rebooted]

Where:
  b, boot_log, -b => Check boot log for errors, ignore the other steps.

  c, check, -c => Check for updates, ignore the other steps.

  p, pcc, -p => Do package cache cleanup, ignore the other steps.

  r, rebooted, -r => A reboot just occurred, so begin at #7 above.

See also:
  - Configurable global defaults are defined in the `Uys::Config`
    constant, at the bottom of this file (<path to uys executable>).
```

## Dependencies

- Arch Linux. If you're on another distro, this tool is not really worth your time, UNLESS you want to use it as a guide for your own tool.
- Ruby 3.1+. Tested on Ruby 3.1, 3.2, and 3.3.
- A not-too-old version of `bash`.
- The `pacman-contrib` Arch package.
- The `aura` tool for AUR management. This could be changed in theory, with minor code updates.

## Configuration

- Search the file for `Config =` to see the main configuration block.
- Typically I'll have `Virtualbox` installed for my systems, so you can see that it's configured to handle the `virtualbox-ext-oracle` package, which is weird for updates because of dependencies with the non-AUR `virtualbox` packages.
- You probably would be interested in the `pkg_cache_clean` config params. For my systems, only the last 2 package files are cached for installed packages, and an uninstalled package gets its cached package files wiped.

## Future plans

- Add more comments and docs.
- Whatever neat things other users might think of.

## Contributing

Well sure, if you want to. Just create an issue and we can go from there.
