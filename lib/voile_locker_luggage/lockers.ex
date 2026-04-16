defmodule VoileLockerLuggage.Lockers do
  @moduledoc """
  Context module for locker management operations.
  """

  @compile {:no_warn_undefined, Voile.Repo}

  import Ecto.Query
  alias Voile.Repo
  alias VoileLockerLuggage.{Locker, LockerSession, LockerNodeConfig}

  # ── Node Config ──────────────────────────────────────────────────────────────

  @doc "List all node configs."
  def list_node_configs do
    Repo.all(LockerNodeConfig)
  end

  @doc "Get node config for a specific node, returns nil if not found."
  def get_node_config(node_id) do
    Repo.get_by(LockerNodeConfig, node_id: node_id)
  end

  @doc "Check if a node has locker system enabled."
  def node_enabled?(node_id) do
    case get_node_config(node_id) do
      %LockerNodeConfig{enabled: true} -> true
      _ -> false
    end
  end

  @doc "Create or update node config."
  def upsert_node_config(node_id, attrs) do
    case get_node_config(node_id) do
      nil ->
        %LockerNodeConfig{}
        |> LockerNodeConfig.changeset(Map.put(attrs, :node_id, node_id))
        |> Repo.insert()

      existing ->
        existing
        |> LockerNodeConfig.changeset(attrs)
        |> Repo.update()
    end
  end

  # ── Lockers ──────────────────────────────────────────────────────────────────

  @doc "List all lockers for a node."
  def list_lockers(node_id) do
    Locker
    |> where([l], l.node_id == ^node_id)
    |> order_by([l], l.locker_number)
    |> Repo.all()
  end

  @doc "List lockers for a node filtered by status."
  def list_lockers(node_id, status) do
    Locker
    |> where([l], l.node_id == ^node_id and l.status == ^status)
    |> order_by([l], l.locker_number)
    |> Repo.all()
  end

  @doc "Get available lockers for a node."
  def list_available_lockers(node_id) do
    list_lockers(node_id, "available")
  end

  @doc "Get a single locker by id."
  def get_locker!(id), do: Repo.get!(Locker, id)

  @doc "Get a locker by node_id and locker_number."
  def get_locker_by_number(node_id, locker_number) do
    Repo.get_by(Locker, node_id: node_id, locker_number: locker_number)
  end

  @doc "Create a new locker."
  def create_locker(attrs) do
    %Locker{}
    |> Locker.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a locker."
  def update_locker(%Locker{} = locker, attrs) do
    locker
    |> Locker.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a locker. Only allowed if no active sessions."
  def delete_locker(%Locker{} = locker) do
    active_count =
      LockerSession
      |> where([s], s.locker_id == ^locker.id and is_nil(s.released_at))
      |> Repo.aggregate(:count, :id)

    if active_count > 0 do
      {:error, :has_active_sessions}
    else
      Repo.delete(locker)
    end
  end

  @doc """
  Bulk-create lockers for a node based on total count.
  Locker numbers are generated as padded integers: \"001\", \"002\", ...
  Only creates lockers that don't already exist.
  """
  def sync_lockers_for_node(node_id, total_count) do
    existing_numbers =
      Locker
      |> where([l], l.node_id == ^node_id)
      |> select([l], l.locker_number)
      |> Repo.all()
      |> MapSet.new()

    desired_numbers =
      1..total_count
      |> Enum.map(&String.pad_leading(Integer.to_string(&1), 3, "0"))
      |> MapSet.new()

    to_create = MapSet.difference(desired_numbers, existing_numbers)

    Repo.transaction(fn ->
      Enum.each(to_create, fn number ->
        %Locker{}
        |> Locker.changeset(%{node_id: node_id, locker_number: number, status: "available"})
        |> Repo.insert!()
      end)

      MapSet.size(to_create)
    end)
  end

  @doc "Count lockers by status for a node."
  def count_lockers_by_status(node_id) do
    Locker
    |> where([l], l.node_id == ^node_id)
    |> group_by([l], l.status)
    |> select([l], {l.status, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ── Sessions ─────────────────────────────────────────────────────────────────

  @doc "List all active sessions for a node."
  def list_active_sessions(node_id) do
    LockerSession
    |> where([s], s.node_id == ^node_id and is_nil(s.released_at))
    |> order_by([s], s.assigned_at)
    |> preload(:locker)
    |> Repo.all()
  end

  @doc "List active sessions for a node with pagination."
  def list_active_sessions(node_id, page, per_page) do
    query =
      LockerSession
      |> where([s], s.node_id == ^node_id and is_nil(s.released_at))
      |> order_by([s], s.assigned_at)
      |> preload(:locker)
      |> limit(^ (per_page + 1))
      |> offset(^((page - 1) * per_page))

    sessions = Repo.all(query)
    has_next_page = length(sessions) > per_page
    sessions = Enum.take(sessions, per_page)

    {sessions, has_next_page}
  end

  @doc "List session history for a node with optional date filter."
  def list_sessions(node_id, opts \\ []) do
    query =
      LockerSession
      |> where([s], s.node_id == ^node_id)
      |> order_by([s], desc: s.assigned_at)
      |> preload(:locker)

    query =
      case Keyword.get(opts, :date) do
        nil ->
          query

        date ->
          start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

          query
          |> where([s], s.assigned_at >= ^start_dt and s.assigned_at < ^end_dt)
      end

    Repo.all(query)
  end

  @doc "List session history for a node with optional date filter and pagination."
  def list_sessions(node_id, date, page, per_page) do
    query =
      LockerSession
      |> where([s], s.node_id == ^node_id)
      |> order_by([s], desc: s.assigned_at)
      |> preload(:locker)

    query =
      case date do
        nil ->
          query

        date ->
          start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

          query
          |> where([s], s.assigned_at >= ^start_dt and s.assigned_at < ^end_dt)
      end

    query =
      query
      |> limit(^ (per_page + 1))
      |> offset(^((page - 1) * per_page))

    sessions = Repo.all(query)
    has_next_page = length(sessions) > per_page
    sessions = Enum.take(sessions, per_page)

    {sessions, has_next_page}
  end

  @doc "Get the active session for a visitor (if any) in a node."
  def get_active_session_for_visitor(node_id, visitor_identifier) do
    LockerSession
    |> where(
      [s],
      s.node_id == ^node_id and s.visitor_identifier == ^visitor_identifier and
        is_nil(s.released_at)
    )
    |> preload(:locker)
    |> Repo.one()
  end

  @doc "Get the active session for a specific locker."
  def get_active_session_for_locker(locker_id) do
    LockerSession
    |> where([s], s.locker_id == ^locker_id and is_nil(s.released_at))
    |> Repo.one()
  end

  @doc """
  Assign a locker to a visitor.
  Automatically picks the first available locker if no locker_id given.
  """
  def assign_locker(node_id, visitor_identifier, visitor_name \\ nil, opts \\ []) do
    locker_id = Keyword.get(opts, :locker_id)
    visitor_log_id = Keyword.get(opts, :visitor_log_id)

    Repo.transaction(fn ->
      locker =
        if locker_id do
          Repo.get!(Locker, locker_id)
        else
          list_available_lockers(node_id) |> List.first()
        end

      cond do
        is_nil(locker) ->
          Repo.rollback(:no_available_lockers)

        locker.status != "available" ->
          Repo.rollback(:locker_not_available)

        true ->
          {:ok, updated_locker} =
            update_locker(locker, %{status: "occupied"})

          attrs = %{
            locker_id: updated_locker.id,
            node_id: node_id,
            visitor_identifier: visitor_identifier,
            visitor_name: visitor_name,
            visitor_log_id: visitor_log_id,
            assigned_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }

          %LockerSession{}
          |> LockerSession.changeset(attrs)
          |> Repo.insert!()
          |> Repo.preload(:locker)
      end
    end)
  end

  @doc "Release a locker session."
  def release_locker(session_id, opts \\ []) do
    release_method = Keyword.get(opts, :release_method, "staff_manual")
    released_by = Keyword.get(opts, :released_by)
    notes = Keyword.get(opts, :notes)

    session = Repo.get!(LockerSession, session_id) |> Repo.preload(:locker)

    if session.released_at do
      {:error, :already_released}
    else
      Repo.transaction(fn ->
        {:ok, _} =
          session
          |> LockerSession.changeset(%{
            released_at: DateTime.utc_now() |> DateTime.truncate(:second),
            release_method: release_method,
            released_by: released_by,
            notes: notes
          })
          |> Repo.update()

        {:ok, _} = update_locker(session.locker, %{status: "available"})

        :ok
      end)
    end
  end

  @doc "Release a visitor's active locker session in a node."
  def release_locker_for_visitor(node_id, visitor_identifier, opts \\ []) do
    case get_active_session_for_visitor(node_id, visitor_identifier) do
      nil -> {:error, :no_active_session}
      session -> release_locker(session.id, opts)
    end
  end

  @doc "Get a session by id with locker preloaded."
  def get_session!(id) do
    LockerSession
    |> Repo.get!(id)
    |> Repo.preload(:locker)
  end
end
