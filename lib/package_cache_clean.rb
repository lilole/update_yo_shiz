# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module PackageCacheClean
  ### A fully controlled, smarter version of the `paccache` Arch Linux command.
    # For the given `pacman` package cache dirs, including any custom dirs used
    # by tools like `yay`, clean out files for the given installed and
    # uninstalled counts.
    # Useful counts are 0 for uninstalled, and 2 for installed. These values
    # ensure that any new package can be rolled back to its previous version,
    # while saving the max disk space.
    # A final prompt is given before deleting anything.
    #
  def package_cache_clean(cache_dirs, cached_files, keep_installed:, keep_uninstalled:)
    Core.new(cache_dirs, cached_files, keep_installed, keep_uninstalled).run
  end

  class Core
    include Mixin::AskContinue
    include Mixin::Cmd
    include Mixin::WithTempFile

    attr :cache_dirs, :cached_files, :file_info, :keep_installed, :keep_uninstalled

    def initialize(cache_dirs, cached_files, keep_installed, keep_uninstalled)
      @cache_dirs       = cache_dirs || []
      @cached_files     = cached_files || []
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
      cache_dirs.each { |dir|
        dir = File.expand_path(dir)
        files = Dir.glob("*-*.pkg.tar*", base: dir)
        files.each { |file| add_file(dir:, file:) }
      }
      cached_files.each { |path| add_file(path:) }
    end

    def add_file(dir: nil, file: nil, path: nil)
      dir  or dir  = File.dirname(path)
      file or file = File.basename(path)
      return if file[-4, 4] == ".sig"
      path or path = File.join(dir, file)
      dir_info[dir] << { path: path, file: file }
      file_info[path] = { dir: dir, file: file }
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
end
