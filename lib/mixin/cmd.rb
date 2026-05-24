# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Mixin
  module Cmd
    ### Join the given strings into a single bash script, and run it in a bash
      # subprocess in its own pseudo-terminal.
      # If `echo` is true, then show the full command to run. If `page` is true,
      # the full command is ellipted to 999 chars max, else it is ellipted to
      # the terminal's columns, or 80 columns if the terminal query fails.
      # If `echo` is an Integer, then show the full command to run after
      # ellipting it to the given value chars max.
      # If `page` is true, then use `less` to page the output.
      # If `page` is a String, then add it as extra options to `less`.
      # If `say_done` is true, then show a final "done" line after the output.
      #
    def cmd(*strings, echo: true, page: true, say_done: true, raw_esc: false)
      @cmd_core ||= Core.new
      @cmd_core.run(strings, echo, page, say_done, raw_esc)
    end

    class Core
      include Mixin::WithTempFile

      def run(strings, echo, page, say_done, raw_esc)
        script = strings.join.gsub(/\A\s+|\n+\z/, "") << "\n"
        say_done and script << "echo '+ Done.'\n"
        less_cmd = page ? %W[less -FIJMRSWX#8 --status-col-width=1] : nil
        less_cmd << "-r" if less_cmd && raw_esc
        String === page and less_cmd.concat(page.strip.split)

        if echo
          less = less_cmd ? " | #{less_cmd.join(" ")}" : ""
          maxw = (Integer === echo) ? echo : (page ? 999 : tty_columns)
          disp = "++ {\n#{script}} 2>&1#{less}".inspect[1..-2].ellipt!(maxw)
          script = "echo #{disp.shellescape}\n#{script}"
        end

        waiter = nil # Must use this scope because `PTY.spawn` ignores block result
        with_temp_file("{\n#{script}}") do |file|
          PTY.spawn(["/usr/bin/bash", "#{self.class.name}#cmd bash"], file) do |pt_out, pt_in, script_pid|
            final_r, final_w = page ? IO.pipe : [$stdin, $stdout]
            writer = write_thread(pt_out, final_w)
            reader = read_thread(writer, pt_in, final_r, page && less_cmd)
            waiter = wait_thread(script_pid, reader, writer, page && [final_w, final_r])
            waiter.join
          end
        end

        waiter.value
      end

    private

      def tty_columns
        n = `stty -a 2> /dev/null`[/\bcolumns (\d+)/, 1]
        n ? n.to_i : 80
      end

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
  end
end
