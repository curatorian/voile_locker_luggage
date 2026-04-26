defmodule VoileLockerLuggage.LockerNodeConfig do
  @moduledoc """
  Stores per-node locker configuration.
  Each node that wants to use the locker system has one record here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "plugin_locker_luggage_node_configs" do
    field(:node_id, :integer)
    field(:enabled, :boolean, default: true)
    field(:total_lockers, :integer, default: 50)
    field(:max_duration_hours, :integer, default: 8)
    field(:notes, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:node_id, :enabled, :total_lockers, :max_duration_hours, :notes])
    |> validate_required([:node_id, :enabled, :total_lockers, :max_duration_hours])
    |> validate_number(:total_lockers, greater_than_or_equal_to: 0)
    |> validate_number(:max_duration_hours, greater_than_or_equal_to: 0)
    |> unique_constraint(:node_id)
  end
end
