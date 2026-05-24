#!/usr/bin/env ruby
#
# Copyright 2024 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

require "io/console"
require "io/wait"
require "pty"
require "set"
require "shellwords"

require_relative "aut_aut"
AutAut.setup

module Uys
  VERSION = ::UpdateYoShiz::VERSION
end

Extensions.apply

## Defaults for all configurable parameters.
 # Some of these can be changed by CLI args, but not all of them.
 #
Uys::Config = {
  boot_log: false,
  checkupd: false,
  pcc:      false,
  rebooted: false,
  pacman: {
    pre_update: {
      uninstalls: %w[virtualbox-ext-oracle]
    }
  },
  yay: {
    post_update: {
      installs: %w[virtualbox-ext-oracle]
    }
  },
  pkg_cache_clean: {
    pkg_dirs:         ["/var/cache/pacman/pkg"],
    pkg_files:        [-> { Dir.glob("#{ENV["HOME"]}/.cache/yay/*/*-*.pkg.tar*") }],
    keep_installed:   2,
    keep_uninstalled: 0
  }
}.as_struct

exit(Uys::Cli.new(ARGV).run) if $0 == __FILE__
