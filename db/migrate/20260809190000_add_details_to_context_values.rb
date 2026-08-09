# frozen_string_literal: true

# Separates DIAGNOSTIC METADATA from the value representation.
#
# The value-representation CHECK (STAT-002) refuses any value on a
# non-observed dimension, and correctly caught an attempt to attach
# `{"source_count" => 0}` to an `unknown` dimension. That payload is not a
# value — it explains why there is no value, which is precisely what STAT-042
# wants ("structured reason codes") and what the Evidence Inspector (§82)
# needs to render.
#
# Relaxing the CHECK to admit value_json would have been the easy fix and the
# wrong one: it would let a real value be smuggled onto a missing dimension
# under a different column name. Metadata gets its own home instead, and the
# invariant stays absolute.
class AddDetailsToContextValues < ActiveRecord::Migration[8.1]
  def change
    # Always permitted, on observed and non-observed dimensions alike, because
    # it never carries the dimension's value.
    add_column :context_values, :details, :jsonb, null: false, default: {}
  end
end
