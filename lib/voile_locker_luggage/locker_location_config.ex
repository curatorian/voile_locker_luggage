defmodule VoileLockerLuggage.LockerLocationConfig do
  @moduledoc """
  Stores per-location locker configuration.
  Each location that should have lockers gets one record here.
  Locations belong to a node, so `node_id` is stored for efficient querying.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "plugin_locker_luggage_location_configs" do
    field(:location_id, :integer)
    field(:node_id, :integer)
    field(:enabled, :boolean, default: true)
    field(:total_lockers, :integer, default: 10)
    field(:notes, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:location_id, :node_id, :enabled, :total_lockers, :notes])
    |> validate_required([:location_id, :node_id, :enabled, :total_lockers])
    |> validate_number(:total_lockers, greater_than: 0)
    |> unique_constraint(:location_id)
  end
end
