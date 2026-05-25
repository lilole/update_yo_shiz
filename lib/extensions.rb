# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Extensions
  def self.apply
    ::Object.include(Object::AsStruct)
    ::String.include(::Ulse::Ext::String::Ellipt)
  end

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
