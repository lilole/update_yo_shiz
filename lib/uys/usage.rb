# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Uys
  module Usage
    def usage(msg=nil, excode=1)
      msg ||= "Online help."
      prog = File.basename($0)
      $stderr << <<~END

        Name:
          UpdateYoShiz #{Uys::VERSION}

        Message:
          #{msg}

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
             9. Check+apply yay updates.
            10. Goto 8 until updates are clear.
            11. Reinstall conflicting AUR packages if needed.
            12. Clear package caches.

        Usage:
          #{prog} [-bcp] [b|boot_log] [c|check] [p|pcc]
          #{prog} [-r|r|rebooted]

        Where:
          b, boot_log, -b => Check boot log for errors, ignore the other steps.

          c, check, -c => Check for updates, ignore the other steps.

          p, pcc, -p => Do package cache cleanup, ignore the other steps.

          r, rebooted, -r => A reboot just occurred, so begin at #7 above.

        See also:
          - Configurable global defaults are defined in the `Uys::Config`
            constant, at the bottom of this file (#{$0}).

      END
      exit(excode) if excode >= 0
    end
  end
end
