# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Uys
  class Core
    include Mixin::AskContinue
    include Mixin::Cmd
    include Mixin::WithTempFile
    include PackageCacheClean

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def run
      steps = []
      config.boot_log and steps << -> { check_system_log(ask: false) }
      config.checkupd and steps << -> { check_all_updates }
      config.pcc      and steps << -> { clear_package_caches(ask: false) }
      steps.empty? and steps << -> { standard_steps }
      steps.each { |step| step[] }
    end

  private

    def standard_steps
      if ! rebooted?
        check_all_updates
        pacman_pre_update
        download_pacman_updates
        apply_pacman_updates
        check_for_pacnew_files
        reboot_maybe
      end
      if rebooted?
        check_system_log
      end
      loop do
        apply_new_pacman_updates
        check_yay_updates
        apply_yay_updates
        ask_continue("Check pacman+yay again?", "yNq") or break
      end
      yay_post_update
      clear_package_caches
    end

    def check_all_updates
      cmd("#{pacman("-Sy --noprogressbar")} && #{pacman("-Qu")}\necho '+ yay:'\n#{yay("-Qua")}")
    end

    def check_pacman_updates
      cmd("#{pacman("-Sy --noprogressbar")} && #{pacman("-Qu")}")
    end

    def pacman_pre_update
      if (pkgs = config.pacman.pre_update.uninstalls)&.any?
        if ask_continue("Uninstall #{pkgs.inspect}?", "yNq")
          cmd(pacman("-Rs --noprogressbar #{pkgs.shelljoin}"), raw_esc: true)
        end
      end
    end

    def download_pacman_updates
      ask_continue("Download needed updates?") or return
      cmd(pacman("-Suyw --noprogressbar"), raw_esc: true)
    end

    def apply_pacman_updates
      puts("\nWARNING: CLOSE EXTRA APP WINDOWS: Updates are about to be applied.")
      ask_continue("Apply downloaded updates?") or return
      cmd(pacman("-Su --noprogressbar"), raw_esc: true)
    end

    def check_for_pacnew_files
      ask_continue("Check for *.pacnew files?") or return
      loop do
        out = `sudo find /boot /etc ! -type d`.each_line.grep(/\.pac\w+$/).join
        if ! out.empty?
          cmd("echo #{out.shellescape}", page: true)
          ask_continue("Check again?") or break
        else
          puts("(None found.)")
          break
        end
      end
    end

    def reboot_maybe
      ask_continue("Reboot now?", "ynq") or return
      `sudo reboot`
      sleep # Just stop, give reboot the time it needs
    end

    def check_system_log(ask: true)
      ask and (ask_continue("Check system log for errors?") or return)
      res = [/warn|error|fail|fatal/i, / kernel: Linux version .+ SMP /]
      out = `journalctl --boot --no-hostname --priority=0..5` # emerg..notice
      out = out.each_line.select { |line| res.any? { _1.match?(line) } }.join
      with_temp_file(out) { |file| cmd("cat #{file}", page: "+G", echo: false) }
    end

    def apply_new_pacman_updates
      ask_continue("Check and apply new pacman updates?") or return
      cmd(pacman("-Suy --noprogressbar"), raw_esc: true)
    end

    def check_yay_updates
      ask_continue("Check yay updates?") or return
      loop do
        cmd(yay("-Qua"))
        ask_continue("Check again?", "yNq") or break
      end
    end

    def apply_yay_updates
      ask_continue("Apply yay updates?", "yNq") or return
      cmd(yay("-Sua"), raw_esc: true)
    end

    def yay_post_update
      if (pkgs = config.yay.post_update.installs)&.any?
        if ask_continue("Install #{pkgs.inspect}?", "yNq")
          cmd(yay("-Sa #{pkgs.shelljoin}"), raw_esc: true)
        end
      end
    end

    def clear_package_caches(ask: true)
      ask and (ask_continue "Clear package caches?" or return)
      Config.pkg_cache_clean.then do |cfg|
        dirs  = cfg.pkg_dirs&.map { |o| Proc === o ? o[] : o }&.flatten
        files = cfg.pkg_files&.map { |o| Proc === o ? o[] : o }&.flatten
        keepi = cfg.keep_installed
        keepu = cfg.keep_uninstalled
        package_cache_clean(dirs, files, keep_installed: keepi, keep_uninstalled: keepu)
      end
    end

    def rebooted? = !! config.rebooted

    def pacman(opts) = "sudo pacman #{opts} --noconfirm --color=always"

    def yay(opts)
      "yay --answerclean=None --answerdiff=None --answeredit=None --answerupgrade=None " \
        "#{opts} --noconfirm --color=always"
    end
  end
end
