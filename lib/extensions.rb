# frozen_string_literal: true
#
# Copyright 2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

module Extensions
  def self.apply
    ::Ulse::Ext::Object::AsGrouping.apply
    ::Ulse::Ext::String::Ellipt.apply
  end
end
