# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Mixin
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
  end
end
