defmodule VoileLockerLuggage.Migrations.CreateLockerTables do
  use Ecto.Migration

  def up do
    # Node-level locker configuration — which nodes have lockers enabled and how many
    create table(:plugin_locker_luggage_node_configs, primary_key: false) do
      add(:id, :binary_id, primary_key: true, null: false, default: fragment("gen_random_uuid()"))
      add(:node_id, :integer, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:total_lockers, :integer, null: false, default: 50)
      add(:max_duration_hours, :integer, null: false, default: 8)
      add(:notes, :text)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:plugin_locker_luggage_node_configs, [:node_id]))

    # Individual lockers
    create table(:plugin_locker_luggage_lockers, primary_key: false) do
      add(:id, :binary_id, primary_key: true, null: false, default: fragment("gen_random_uuid()"))
      add(:node_id, :integer, null: false)
      add(:locker_number, :string, null: false)
      add(:status, :string, null: false, default: "available")
      # available | occupied | maintenance | reserved
      add(:notes, :text)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:plugin_locker_luggage_lockers, [:node_id, :locker_number]))
    create(index(:plugin_locker_luggage_lockers, [:node_id]))
    create(index(:plugin_locker_luggage_lockers, [:status]))

    # Locker sessions — tracks who is using a locker and when
    create table(:plugin_locker_luggage_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true, null: false, default: fragment("gen_random_uuid()"))

      add(
        :locker_id,
        references(:plugin_locker_luggage_lockers, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:node_id, :integer, null: false)
      add(:visitor_identifier, :string, null: false)
      add(:visitor_name, :string)
      add(:visitor_log_id, :integer)
      # reference to visitor_logs if available
      add(:assigned_at, :utc_datetime, null: false)
      add(:released_at, :utc_datetime)
      add(:release_method, :string)
      # "visitor_self" | "staff_manual" | "auto_expired"
      add(:released_by, :string)
      # staff user email or nil
      add(:notes, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:plugin_locker_luggage_sessions, [:locker_id]))
    create(index(:plugin_locker_luggage_sessions, [:node_id]))
    create(index(:plugin_locker_luggage_sessions, [:visitor_identifier]))
    create(index(:plugin_locker_luggage_sessions, [:assigned_at]))
    create(index(:plugin_locker_luggage_sessions, [:released_at]))
  end

  def down do
    drop(table(:plugin_locker_luggage_sessions))
    drop(table(:plugin_locker_luggage_lockers))
    drop(table(:plugin_locker_luggage_node_configs))
  end
end
