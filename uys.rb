#!/usr/bin/env ruby
#
# Copyright 2024 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

require "io/console"
require "set"
require "shellwords"

module Uys
  module Usage
    def usage(msg=nil, excode=1)
      msg ||= "Online help."
      $stderr << <<~END

        Name:
          UpdateYoShiz

        Message:
          #{msg}

        Description:
          Automates all the steps normally taken to update Danamis machines:
             1. Check pacman updates.
             2. Download pacman updates.
             3. Apply pacman downloaded updates. Warn to close all apps first.
             4. Check for new *.pacnew files.
             5. Reboot if needed.
             6. Check system log for (new) error messages, if rebooted.
             7. Check+apply pacman updates.
             8. Check+apply pikaur updates.
             9. Goto 7 until updates are clear.
            10. Clear package caches.

        Usage:
          #{$0} [-r|--rebooted]
          #{$0} [-b|boot_log] [-c|check] [-p|pcc]

        Where:
          -r, --rebooted => A reboot just occurred, so begin at #6 above.

          boot_log, -b => Check boot log for errors, ignore the other steps.

          check, -c => Check for updates, ignore the other steps.

          pcc, -p => Do package cache cleanup, ignore the other steps.

      END
      exit(excode) if excode >= 0
    end
  end # Usage

  # ___________________________________________________________________________

  module Extensions
    def self.apply
      ::Object.instance_methods.member?(:as_struct) or ::Object.include(Object::AsStruct)
    end

    module Object
      module AsStruct
        def as_struct
          if respond_to?(:keys) && respond_to?(:values)
            Struct.new(*keys.map(&:to_sym)).new(*values.map(&:as_struct))
          elsif respond_to?(:map)
            map(&:as_struct)
          else
            self
          end
        end
      end # AsStruct
    end # Object
  end # Extensions

  # ___________________________________________________________________________

  Extensions.apply

  Config = {
    boot_log: false,
    checkupd: false,
    pcc:      false,
    rebooted: false,
    pacman: {
      pre_update: {
        uninstalls: %w[virtualbox-ext-oracle]
      }
    },
    pikaur: {
      post_update: {
        installs: %w[virtualbox-ext-oracle]
      }
    },
    pkg_cache_clean: {
      pkg_dirs: %W[#{ENV["HOME"]}/.cache/pikaur/pkg /var/cache/pacman/pkg],
      keep_installed: 2,
      keep_uninstalled: 0
    }
  }.as_struct # Config

  # ___________________________________________________________________________

  module Util
    def cmd(*strings, echo: true, page: nil, say_done: true)
      script = disp = strings.join
      disp = disp.inspect if disp.include?("\n")
      less = page ? +" | less -FIJMRSWX" : nil
      if less
        less << " #{page}" if String === page
        disp = "{ #{disp}; } 2>&1#{less}"
      end
      if echo
        say_done and script = "#{script}; echo '+ Done.'"
        script = "{ echo '++ '#{disp.shellescape}; #{script}; } 2>&1#{less}"
      else
        say_done and script = "{ #{script}; echo '+ Done.'; }"
        script = "#{script} 2>&1#{less}"
      end
      system(["/usr/bin/bash", "#{self.class.name}#cmd bash"], "-c", script)
    end

    def ask_continue(prompt="Continue?", opts="Ynq")
      def_reply = opts.gsub(/[a-z]+/, "")
      raise "Only 1 uppercase is allowed: #{opts.inspect}" if def_reply.size > 1
      $stderr.puts("")
      until nil
        $stderr.write("#{prompt} [#{opts}] ")
        reply = $stdin.getch(intr: true).chomp
        reply = def_reply if reply.empty? && def_reply
        lreply = reply.downcase
        $stderr.puts(lreply)
        break if lreply =~ /^[#{opts.downcase}]$/
      end
      $stderr.puts("")
      exit if lreply == "q"
      lreply == "y"
    end
  end # Util

  # ___________________________________________________________________________

  class Core
    include Util

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def run
      steps = []
      config.checkupd && steps << -> { check_all_updates }
      config.boot_log && steps << -> { check_system_log(ask: false) }
      config.pcc      && steps << -> { clear_package_caches(ask: false) }
      steps.empty? and steps << -> { standard_steps }
      steps.each { |step| step.call }
    end

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
        check_pikaur_updates
        apply_pikaur_updates
        ask_continue("Check pacman+pikaur again?", "yNq") or break
      end
      pikaur_post_update
      clear_package_caches
    end

    def check_all_updates
      cmd("{ checkupdates; echo; #{pikaur("-Qu")}; }", page: true)
    end

    def check_pacman_updates
      cmd("checkupdates", page: true)
    end

    def pacman_pre_update
      if (pkgs = config.pacman.pre_update.uninstalls)&.any?
        if ask_continue("Uninstall #{pkgs.inspect}?", "yNq")
          cmd(pacman("-Rs #{pkgs.shelljoin}"), page: "-r")
        end
      end
    end

    def download_pacman_updates
      ask_continue("Download needed updates?") or return
      cmd(pacman("-Suyw"), page: "-r")
    end

    def apply_pacman_updates
      puts("\nWARNING: CLOSE EXTRA APP WINDOWS: Updates are about to be applied.")
      ask_continue("Apply downloaded updates?") or return
      cmd(pacman("-Su"), page: "-r +F")
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
    end

    def check_system_log(ask: true)
      ask and (ask_continue("Check system log for errors?") or return)
      out = `journalctl -b | head -n 10`
      lines = []
      out.each_line do |line|
        lines << line
        line =~ / kernel: Linux version .+ SMP / and break
        lines.size >= 10 and (lines.clear; break)
      end
      out = lines.join << `journalctl -b | egrep -i 'error|warn|fail|fatal' 2>&1`
      cmd("echo #{out.shellescape}", page: "+G", echo: false)
    end

    def apply_new_pacman_updates
      ask_continue("Check and apply new pacman updates?") or return
      cmd(pacman("-Suy"), page: "-r")
    end

    def check_pikaur_updates
      ask_continue("Check pikaur updates?") or return
      loop do
        cmd(pikaur("-Qu"), page: true)
        ask_continue("Check again?", "yNq") or break
      end
    end

    def apply_pikaur_updates
      ask_continue("Apply pikaur updates?") or return
      cmd(pikaur("-Su"), page: "-r +F")
    end

    def pikaur_post_update
      if (pkgs = config.pikaur.post_update.installs)&.any?
        if ask_continue("Install #{pkgs.inspect}?", "yNq")
          cmd(pikaur("-S #{pkgs.shelljoin}"), page: "-r +F")
        end
      end
    end

    def clear_package_caches(ask: true)
      ask and (ask_continue "Clear package caches?" or return)
      Config.pkg_cache_clean.then do |cfg|
        dirs  = cfg.pkg_dirs
        keepi = cfg.keep_installed
        keepu = cfg.keep_uninstalled
        PackageCacheClean.new(dirs, keep_installed: keepi, keep_uninstalled: keepu).run
      end
    end

    def rebooted? = !! config.rebooted

    def pacman(opts) = "sudo pacman --noconfirm --noprogressbar --color always #{opts}"

    def pikaur(opts) = "pikaur -a --noconfirm #{opts}"
  end # Core

  # ___________________________________________________________________________

  class PackageCacheClean
    include Util

    attr_reader :cache_dirs, :dir_info, :file_info, :keep_installed, :keep_uninstalled, :pkg_info

    def initialize(cache_dirs, keep_installed:, keep_uninstalled:)
      @cache_dirs       = cache_dirs
      @keep_installed   = keep_installed
      @keep_uninstalled = keep_uninstalled
      @markedi = @markedu = 0
    end

    def run
      find_package_files
      sort_list_by_version
      group_list_by_pkg_name
      mark_list_by_keepu_rules
      mark_list_by_keepi_rules
      remove_marked_files
    end

    def find_package_files
      @dir_info = Hash.new { |h, k| h[k] = [] }
      @file_info = {}
      cache_dirs.each do |dir|
        dir = File.expand_path(dir)
        begin
          Dir.glob("*-*.pkg.tar*", base: dir)
        end.each do |file|
          next if file[-4, 4] == ".sig"
          path = File.join(dir, file)
          dir_info[dir] << { path: path, file: file }
          file_info[path] = { dir: dir, file: file }
        end
      end
    end

    def sort_list_by_version
      index = -1
      dir_info.each do |dir, infos|
        paths = infos.map { |h| h[:path] }
        out = Dir.chdir(dir) { `echo #{paths.join("\n").shellescape} | pacsort --files` }
        out.strip.split("\n").each do |path|
          file_info[path][:index] = (index += 1)
        end
      end
      @dir_info = nil # Release mem
    end

    def group_list_by_pkg_name
      @pkg_info = Hash.new { |h, k| h[k] = [] }
      file_info.each do |path, info|
        begin
          name = info[:file]
          raise if ! (rem = /\A(.+)-[^-]+\z/.match(name))
          parts = rem[1].split("-")
          raise if parts.size < 3
          pname = parts[0..-3].join("-")  # Pkg name can have "-"
          pver  = parts[-2..-1].join("-") # Always pkgver-pkgrel
        rescue
          $stderr << "Warning: Could not parse name: #{name.inspect}\n"
          next
        end
        file_info[path][:pkg]     = pname
        file_info[path][:version] = pver
        pkg_info[pname] << file_info[path]
      end
    end

    def mark_list_by_keepu_rules
      pkg_info.each_key do |pkg|
        @markedu += mark_for_delete(pkg, keep: keep_uninstalled) if ! installed_pkgs.member?(pkg)
      end
    end

    def mark_list_by_keepi_rules
      pkg_info.each_key do |pkg|
        @markedi += mark_for_delete(pkg, keep: keep_installed) if installed_pkgs.member?(pkg)
      end
    end

    def installed_pkgs = @installed_pkgs ||= `pacman -Qsq`.strip.split("\n").to_set

    def remove_marked_files
      marked = file_info.select { |_path, info| info[:delete] }.map { |path, _info| Dir.glob("#{path}*") }.flatten

      text = []
      text << "+ Total #{pkg_info.size} packages from #{file_info.size} files."
      text << "+ Marked #{@markedi} installed package files for delete."
      text << "+ Marked #{@markedu} uninstalled package files for delete."
      marked.each { |path| text << "+ Marked: #{path.inspect}" if path[-4, 4] != ".sig" }

      cmd("echo #{text.join("\n").shellescape}", page: true, echo: false, say_done: false)
      return if marked.size == 0

      ask_continue "Are you sure?" or return
      sudos = marked.select { |path| ! File.writable?(path) }
      marked -= sudos
      `sudo rm #{sudos.shelljoin}` if sudos.any?
      `rm #{marked.shelljoin}` if marked.any?
      puts "+ Done."
    end

    def mark_for_delete(pkg, keep:)
      return 0 if pkg_info[pkg].size < keep
      marked = 0
      sorted_infos = pkg_info[pkg].sort { |a, b| b[:index] <=> a[:index] }
      sorted_infos[keep..-1].each { |info| info[:delete] = true; marked += 1 }
      marked
    end
  end # PackageCacheClean

  # ___________________________________________________________________________

  class Cli
    include Usage

    attr_reader :args

    def initialize(args)
      @args = args
    end

    def run
      raise "A tty is required" if ! $stdin.tty?
      parse_args
      Core.new(Config).run
      true
    rescue => e
      $stderr << e.full_message
      false
    end

    def parse_args
      Config.rebooted = false
      idx = -1
      while (arg = args[idx += 1])
        ok = 0
        arg =~ %r`^-[^-]*[h?]|^--help$`  && ok = 1 and usage
        arg =~ %r`^-[^-]*r|^--rebooted$` && ok = 1 and Config.rebooted = true
        arg =~ %r`^-[^-]*b|^boot_log$`   && ok = 1 and Config.boot_log = true
        arg =~ %r`^-[^-]*c|^check$`      && ok = 1 and Config.checkupd = true
        arg =~ %r`^-[^-]*p|^pcc$`        && ok = 1 and Config.pcc = true
        usage "Invalid arg: #{arg.inspect}" if ok < 1
      end
    end
  end # Cli
end # Uys

exit(Uys::Cli.new(ARGV).run) if $0 == __FILE__
