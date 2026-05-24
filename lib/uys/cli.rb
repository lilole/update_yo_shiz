# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Uys
  class Cli
    include Uys::Usage

    attr_reader :args

    def initialize(args)
      @args = args
    end

    def run
      raise "A tty is required" if ! $stdin.tty?
      parse_args
      Uys::Core.new(Config).run
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
  end
end
