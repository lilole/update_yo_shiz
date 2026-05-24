# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

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
end
