defmodule VoileLockerLuggage.Locker do
  @moduledoc """
  Represents a physical locker unit in a node.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["available", "occupied", "maintenance", "reserved"]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "plugin_locker_luggage_lockers" do
    field(:node_id, :integer)
    field(:locker_number, :string)
    field(:status, :string, default: "available")
    field(:notes, :string)

    has_many(:sessions, VoileLockerLuggage.LockerSession, foreign_key: :locker_id)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(locker, attrs) do
    locker
    |> cast(attrs, [:node_id, :locker_number, :status, :notes])
    |> validate_required([:node_id, :locker_number, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:node_id, :locker_number])
  end

  def statuses, do: @statuses
end
