defmodule VoileLockerLuggage.LockerSession do
  @moduledoc """
  Tracks who is currently using or has used a locker.
  An active session has released_at == nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @release_methods ["visitor_self", "staff_manual", "auto_expired"]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "plugin_locker_luggage_sessions" do
    field(:node_id, :integer)
    field(:visitor_identifier, :string)
    field(:visitor_name, :string)
    field(:visitor_log_id, :integer)
    field(:assigned_at, :utc_datetime)
    field(:released_at, :utc_datetime)
    field(:release_method, :string)
    field(:released_by, :string)
    field(:notes, :string)

    belongs_to(:locker, VoileLockerLuggage.Locker, type: :binary_id)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :locker_id,
      :node_id,
      :visitor_identifier,
      :visitor_name,
      :visitor_log_id,
      :assigned_at,
      :released_at,
      :release_method,
      :released_by,
      :notes
    ])
    |> validate_required([:locker_id, :node_id, :visitor_identifier, :assigned_at])
    |> validate_inclusion(:release_method, @release_methods, allow_nil: true)
  end

  def release_methods, do: @release_methods

  def active?(session) do
    is_nil(session.released_at)
  end
end
