#!/usr/bin/env ruby
#
# Copyright 2024 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

require "io/console"
require "io/wait"
require "pty"
require "set"
require "shellwords"

module Uys
  class Cli
    def usage(msg=nil, excode=1)
      msg ||= "Online help."
      prog = File.basename($0)
      $stderr << <<~END

        Name:
          UpdateYoShiz

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
             9. Check+apply pikaur updates.
            10. Goto 7 until updates are clear.
            11. Reinstall conflicting AUR packages if needed.
            12. Clear package caches.

        Usage:
          #{prog} [-bcp] [b|boot_log] [c|check] [p|pcc]
          #{prog} [-r|r|rebooted]

        Where:
          b, boot_log, -b => Check boot log for errors, ignore the other steps.

          c, check, -c => Check for updates, ignore the other steps.

          p, pcc, -p => Do package cache cleanup, ignore the other steps.

          r, rebooted, -r => A reboot just occurred, so begin at #6 above.

      END
      exit(excode) if excode >= 0
    end
  end # Cli
end # Uys

module Extensions
  def self.apply
    ::Object.include(Object::AsStruct)
    ::String.include(String::Ellipt)
  end

  module String
    module Ellipt
      ### Trim self to given width with ellipsis in the middle and return self.
        #
      def ellipt!(width, ellipsis="...")
        e_sz = ellipsis.size
        return replace(ellipsis) if width <= e_sz
        return self if size <= width
        chunk, carry = (width - e_sz).divmod(2)
        (0...e_sz).each  { |i| self[chunk + carry + i] = ellipsis[i] }
        (0...chunk).each { |i| self[chunk + carry + e_sz + i] = self[size - chunk + i] }
        slice!(width, size - width)
        self
      end

      ### Trim a copy of self to given width with ellipsis in the middle and
        # return it.
        #
      def ellipt(width, ellipsis="...")
        dup.ellipt!(width, ellipsis)
      end
    end # Ellipt
  end # String

  module Object
    module AsStruct
      ### Recursively convert Hash-like objects within self to Struct objects,
        # so that keys become accessible as method names.
        # This is helpful because (a) code is more readable, and (b) access to
        # Struct values is much faster than OpenStruct.
        #
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

Extensions.apply # Add early for use by constants

module Mixin
  module AskContinue
    ### Present a single-line prompt with single-character response choices.
      # A single uppercase choice is default if Enter is pressed.
      #
    def ask_continue(prompt="Continue?", opts="Ynq")
      def_reply = opts.gsub(/[^A-Z]+/, "")
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
  end # AskContinue

  module WithTempFile
    ### Run the given block after saving the given body to a unique temp file,
      # with the file's path passed to the block.
      #
    def with_temp_file(body="")
      @with_temp_file_count ||= 0

      begin
        c = (@with_temp_file_count += 1)
        file = "/tmp/#{File.basename($0)}.#{__id__}.#{c}.tmp"
      end while File.exist?(file)

      File.write(file, body)
      begin
        yield(file)
      ensure
        File.delete(file) rescue nil
      end
    end
  end # WithTempFile

  module Cmd
    ### Join the given strings into a single bash script, and run it in a bash
      # subprocess in its own pseudo-terminal.
      # If `echo` is true, then show the full command to run after ellipting it
      # to 80 chars max, or 199 chars max if `page` is true.
      # If `echo` is an Integer, then show the full command to run after
      # ellipting it to the given value chars max.
      # If `page` is true, then use `less` to page the output.
      # If `say_done` is true, then show a final "done" line after the output.
      #
    def cmd(*strings, echo: true, page: true, say_done: true)
      @cmd_core ||= Core.new
      @cmd_core.run(strings, echo, page, say_done)
    end

    class Core
      include Mixin::WithTempFile

      def run(strings, echo, page, say_done)
        script = strings.join.gsub(/\A\s+|\n+\z/, "") << "\n"
        script << "echo '+ Done.'\n" if say_done
        less_opts = page ? %w[-FIJMrSWX#8 --status-col-width=1] : nil
        less_opts.concat(page.strip.split) if String === page

        if echo
          less = page ? " | less #{less_opts.join(" ")}" : ""
          disp = "++ {\n#{script}} 2>&1#{less}".inspect[1..-2]
          maxw = (Integer === echo) ? echo : (page ? 199 : 80)
          disp.ellipt!(maxw)
          script = "echo #{disp.shellescape}\n#{script}"
        end

        waiter = nil # Must use this scope because `PTY.spawn` ignores block result
        with_temp_file("{\n#{script}}") do |file|
          PTY.spawn(["/usr/bin/bash", "#{self.class.name}#cmd bash"], file) do |pt_out, pt_in, script_pid|
            final_r, final_w = page ? IO.pipe : [$stdin, $stdout]
            writer = write_thread(pt_out, final_w)
            reader = read_thread(writer, pt_in, final_r, page && ["less"].concat(less_opts))
            waiter = wait_thread(script_pid, reader, writer, page && [final_w, final_r])
            waiter.join
          end
        end

        waiter.value
      end

    private

      def write_thread(pt_out, write_end)
        Thread.new do
          loop do
            begin
              write_end.write(pt_out.read(1))
            rescue Errno::EIO
              break
            end
          end
        end
      end

      def read_thread(writer, pt_in, read_end, pager_args)
        Thread.new do
          if pager_args
            system(*pager_args, in: read_end)
          else
            read_end.raw do
              loop do
                break if ! writer.alive?
                pt_in.write(read_end.getch) if read_end.wait_readable(0.1)
              end
            end
          end
        end
      end

      def wait_thread(pt_pid, reader, writer, closes)
        Thread.new do
          Process.wait(pt_pid)
          $?.tap do
            writer.join
            closes.each(&:close) if closes
            reader.join
          end
        end
      end
    end # Core
  end # Cmd
end # Mixin

module PackageCacheClean
  ### A fully controlled, smarter version of the `paccache` Arch Linux command.
    # For the given `pacman` package cache dirs, including any custom dirs used
    # by tools like `pikaur`, clean out files for the given installed and
    # uninstalled counts.
    # Useful counts are 0 for uninstalled, and 2 for installed. These values
    # ensure that any new package can be rolled back to its previous version,
    # while saving the max disk space.
    # A final prompt is given before deleting anything.
    #
  def package_cache_clean(cache_dirs, keep_installed:, keep_uninstalled:)
    Core.new(cache_dirs, keep_installed, keep_uninstalled).run
  end

  class Core
    include Mixin::AskContinue
    include Mixin::Cmd
    include Mixin::WithTempFile

    attr_reader :cache_dirs, :file_info, :keep_installed, :keep_uninstalled

    def initialize(cache_dirs, keep_installed, keep_uninstalled)
      @cache_dirs       = cache_dirs
      @keep_installed   = keep_installed
      @keep_uninstalled = keep_uninstalled
    end

    def run
      find_package_files
      sort_list_by_version
      group_list_by_pkg_name
      mark_list_by_keepu_rules
      mark_list_by_keepi_rules
      remove_marked_files
    end

  private

    def find_package_files
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

    def dir_info = @dir_info ||= Hash.new { |h, k| h[k] = [] }

    def file_info = @file_info ||= {}

    def sort_list_by_version
      index = -1
      dir_info.each do |dir, infos|
        paths = infos.map { |h| h[:path] }.join("\n") << "\n" # pacsort requires last LF
        out = with_temp_file(paths) { |file| `pacsort --files < #{file}` }
        out.strip.split("\n").each do |path|
          file_info[path][:index] = (index += 1)
        end
      end
    end

    def group_list_by_pkg_name
      file_info.each do |path, finfo|
        begin
          name = finfo[:file]
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
        pkg_info[pname][:file_infos] << file_info[path]
        pkg_info[pname][:installed]   = installed_pkgs.member?(pname)
      end
    end

    def pkg_info
      @pkg_info ||= begin
        Hash.new do |pinfo, pname|
          pinfo[pname] = Hash.new do |h, k|
            if   k == :file_infos then h[k] = []
            else nil
            end
          end
        end
      end
    end

    def installed_pkgs = @installed_pkgs ||= `pacman -Qsq`.split("\n").to_set

    def mark_list_by_keepu_rules
      @markedu = 0
      pkg_info.each do |pkg, info|
        @markedu += mark_for_delete(pkg, keep: keep_uninstalled) if ! info[:installed]
      end
    end

    def mark_list_by_keepi_rules
      @markedi = 0
      pkg_info.each do |pkg, info|
        @markedi += mark_for_delete(pkg, keep: keep_installed) if info[:installed]
      end
    end

    def mark_for_delete(pkg, keep:)
      return 0 if pkg_info[pkg][:file_infos].size < keep
      marked = 0
      sorted_infos = pkg_info[pkg][:file_infos].sort { |a, b| b[:index] <=> a[:index] }
      sorted_infos[keep..-1].each { |info| info[:delete] = true; marked += 1 }
      marked
    end

    def remove_marked_files
      text = []; marked = []; del_bytes = 0
      text << "+ Total #{pkg_info.size} packages from #{file_info.size} files."
      text << "+ Marked #{@markedi} installed package files for delete."
      text << "+ Marked #{@markedu} uninstalled package files for delete."
      file_info.select do |_path, finfo|
        finfo[:delete]
      end.each do |path, finfo|
        Dir.glob("#{path}*").each do |path2| # Need glob for .sig files
          marked << path2
          del_bytes += File.size(path2)
          next if path2[-4, 4] == ".sig"
          type = pkg_info[finfo[:pkg]][:installed] ? "I" : "U"
          text << "+ Marked: #{type}: #{path.inspect}"
        end
      end
      text << "+ Total %3.1f MB (%d bytes) marked for delete." % [del_bytes / 1e6, del_bytes]

      with_temp_file(text.join("\n")) do |file|
        cmd("cat #{file}", echo: false, say_done: false)
      end
      return if marked.size == 0
      ask_continue "Are you sure?" or return

      sudos = marked.select { |path| ! File.writable?(path) }
      marked -= sudos

      sudos.any?  and sudos.each_slice(20)  { |paths| `sudo rm #{paths.shelljoin}` }
      marked.any? and marked.each_slice(20) { |paths| `rm #{paths.shelljoin}` }

      puts "+ Done."
    end
  end # Core
end # PackageCacheClean

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
        check_pikaur_updates
        apply_pikaur_updates
        ask_continue("Check pacman+pikaur again?", "yNq") or break
      end
      pikaur_post_update
      clear_package_caches
    end

    def check_all_updates
      cmd("checkupdates \necho \n#{pikaur("-Qu")}")
    end

    def check_pacman_updates
      cmd("checkupdates")
    end

    def pacman_pre_update
      if (pkgs = config.pacman.pre_update.uninstalls)&.any?
        if ask_continue("Uninstall #{pkgs.inspect}?", "yNq")
          cmd(pacman("-Rs #{pkgs.shelljoin}"))
        end
      end
    end

    def download_pacman_updates
      ask_continue("Download needed updates?") or return
      cmd(pacman("-Suyw"))
    end

    def apply_pacman_updates
      puts("\nWARNING: CLOSE EXTRA APP WINDOWS: Updates are about to be applied.")
      ask_continue("Apply downloaded updates?") or return
      cmd(pacman("-Su"))
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
      with_temp_file(out) { |file| cmd("cat #{file}", page: "+G", echo: true) }
    end

    def apply_new_pacman_updates
      ask_continue("Check and apply new pacman updates?") or return
      cmd(pacman("-Suy"))
    end

    def check_pikaur_updates
      ask_continue("Check pikaur updates?") or return
      loop do
        cmd(pikaur("-Qu"))
        ask_continue("Check again?", "yNq") or break
      end
    end

    def apply_pikaur_updates
      ask_continue("Apply pikaur updates?", "yNq") or return
      cmd(pikaur("-Su"))
    end

    def pikaur_post_update
      if (pkgs = config.pikaur.post_update.installs)&.any?
        if ask_continue("Install #{pkgs.inspect}?", "yNq")
          cmd(pikaur("-S #{pkgs.shelljoin}"))
        end
      end
    end

    def clear_package_caches(ask: true)
      ask and (ask_continue "Clear package caches?" or return)
      Config.pkg_cache_clean.then do |cfg|
        dirs  = cfg.pkg_dirs
        keepi = cfg.keep_installed
        keepu = cfg.keep_uninstalled
        package_cache_clean(dirs, keep_installed: keepi, keep_uninstalled: keepu)
      end
    end

    def rebooted? = !! config.rebooted

    def pacman(opts) = "sudo pacman --noconfirm --color=always #{opts}"

    def pikaur(opts) = "pikaur -a --noconfirm --color=always #{opts}"
  end # Core

  class Cli
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

  private

    def parse_args
      Config.rebooted = false
      idx = -1
      while (arg = args[idx += 1])
        arg =~ /^-[^-]*[h?]|^--help$/ and usage
        ok = 0
        arg =~ /^-[^-]*b|^b$|^boot_log$/ && ok = 1 and Config.boot_log = true
        arg =~ /^-[^-]*c|^c$|^check$/    && ok = 1 and Config.checkupd = true
        arg =~ /^-[^-]*p|^p$|^pcc$/      && ok = 1 and Config.pcc = true
        arg =~ /^-[^-]*r|^r$|^rebooted$/ && ok = 1 and Config.rebooted = true
        usage "Invalid arg: #{arg.inspect}" if ok < 1
      end
    end
  end # Cli

  ### Defaults for all configurable parameters.
    # Some of these can be changed by CLI args, but not all of them.
    #
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
  }.as_struct
end # Uys

exit(Uys::Cli.new(ARGV).run) if $0 == __FILE__
