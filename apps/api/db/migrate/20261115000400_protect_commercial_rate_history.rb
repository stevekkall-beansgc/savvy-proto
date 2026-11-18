class ProtectCommercialRateHistory < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE FUNCTION commercial_rates_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'commercial rate history is append-only'; END;
      $$;
      CREATE TRIGGER commercial_rates_no_update_delete BEFORE UPDATE OR DELETE ON commercial_rates FOR EACH ROW EXECUTE FUNCTION commercial_rates_append_only();
    SQL
  end
  def down
    execute 'DROP TRIGGER commercial_rates_no_update_delete ON commercial_rates'
    execute 'DROP FUNCTION commercial_rates_append_only()'
  end
end
