# frozen_string_literal: true
#
# Copyright 2024-2026 Dan Higgins
# SPDX-License-Identifier: Apache-2.0

load "../ultisel/load/arma.rake" # ...sorry this is not public yet

arma.import arma: "../ultisel", version: nil, build: true,
  include: [
    Ulse.minimum_custom_includes,
    '^ulse/ext/string\.rb',
    '^ulse/ext/string/ellipt\.rb'
  ]
