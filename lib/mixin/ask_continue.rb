# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

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
  end
end
