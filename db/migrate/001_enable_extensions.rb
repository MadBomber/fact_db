# frozen_string_literal: true

class EnableExtensions < ActiveRecord::Migration[7.0]
  def change
    enable_extension "vector" unless extension_enabled?("vector")
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
  end
end
