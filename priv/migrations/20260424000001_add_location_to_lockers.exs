defmodule VoileLockerLuggage.Migrations.AddLocationToLockers do
  use Ecto.Migration

  def up do
    # Add nullable location_id to existing lockers
    alter table(:plugin_locker_luggage_lockers) do
      add(:location_id, :integer, null: true)
    end

    create(index(:plugin_locker_luggage_lockers, [:location_id]))

    # Drop the old node-level unique index and replace with two partial unique indexes:
    # 1. For lockers WITHOUT a location: unique by (node_id, locker_number)
    # 2. For lockers WITH a location: unique by (location_id, locker_number)
    drop(unique_index(:plugin_locker_luggage_lockers, [:node_id, :locker_number]))

    execute("""
    CREATE UNIQUE INDEX plugin_locker_luggage_lockers_node_number_idx
    ON plugin_locker_luggage_lockers (node_id, locker_number)
    WHERE location_id IS NULL
    """)

    execute("""
    CREATE UNIQUE INDEX plugin_locker_luggage_lockers_location_number_idx
    ON plugin_locker_luggage_lockers (location_id, locker_number)
    WHERE location_id IS NOT NULL
    """)

    # Per-location locker configuration
    create table(:plugin_locker_luggage_location_configs, primary_key: false) do
      add(:id, :binary_id, primary_key: true, null: false, default: fragment("gen_random_uuid()"))
      add(:location_id, :integer, null: false)
      add(:node_id, :integer, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:total_lockers, :integer, null: false, default: 10)
      add(:notes, :text)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:plugin_locker_luggage_location_configs, [:location_id]))
    create(index(:plugin_locker_luggage_location_configs, [:node_id]))
  end

  def down do
    drop(table(:plugin_locker_luggage_location_configs))

    execute("DROP INDEX IF EXISTS plugin_locker_luggage_lockers_node_number_idx")
    execute("DROP INDEX IF EXISTS plugin_locker_luggage_lockers_location_number_idx")

    create(unique_index(:plugin_locker_luggage_lockers, [:node_id, :locker_number]))

    alter table(:plugin_locker_luggage_lockers) do
      remove(:location_id)
    end
  end
end
