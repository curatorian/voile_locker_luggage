defmodule VoileLockerLuggage do
  @moduledoc """
  Voile Locker & Luggage plugin.

  Provides locker management for visitor check-in flows.
  Each node can independently enable or disable the locker system
  and configure how many lockers are available.

  ## Features

  - Per-node locker enable/disable toggle
  - Configurable locker count per node
  - Auto-assign available locker during visitor check-in
  - Manual locker assignment and release by staff
  - Locker status: available, occupied, maintenance, reserved
  - Session history with timestamps and release tracking
  - Admin management UI at /manage/plugins/locker_luggage/
  """

  # Implements Voile.Plugin behaviour (validated at runtime — host app not available at plugin compile time)
  @compile {:no_warn_undefined, [Voile.Plugin, Voile.Hooks]}
  # @impl true is omitted below because Voile.Plugin behaviour cannot be loaded at
  # plugin compile time (path dep compiled before host app). Validated at runtime.

  require Logger

  def metadata do
    %{
      id: "locker_luggage",
      name: "Locker & Luggage",
      version: "1.0.0",
      author: "Voile",
      description:
        "Visitor locker management system with per-node configuration and check-in integration.",
      license_type: :free,
      icon: "hero-archive-box",
      tags: ["visitor", "locker", "luggage"]
    }
  end

  def on_install do
    Logger.info("[VoileLockerLuggage] Running migrations...")

    case VoileLockerLuggage.Migrator.run() do
      {:ok, _} ->
        Logger.info("[VoileLockerLuggage] Migrations applied successfully.")
        :ok

      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("[VoileLockerLuggage] Migration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def on_activate do
    Voile.Hooks.register(:visitor_check_in_panels, &__MODULE__.check_in_panels_hook/1,
      owner: __MODULE__,
      priority: 10
    )

    :ok
  end

  def on_deactivate do
    Voile.Hooks.unregister_all(__MODULE__)
    :ok
  end

  def on_uninstall do
    Logger.info("[VoileLockerLuggage] Rolling back migrations...")

    case VoileLockerLuggage.Migrator.rollback() do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def on_update(_old_version, _new_version) do
    case VoileLockerLuggage.Migrator.run() do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def hooks do
    [
      {:visitor_check_in_panels, &__MODULE__.check_in_panels_hook/1}
    ]
  end

  def routes do
    [
      {"/", VoileLockerLuggage.Web.IndexLive, :index},
      {"/lockers", VoileLockerLuggage.Web.LockersLive, :index},
      {"/sessions", VoileLockerLuggage.Web.SessionsLive, :index},
      {"/nodes", VoileLockerLuggage.Web.NodeConfigLive, :index}
    ]
  end

  def nav do
    [
      %{path: "/", label: "Overview", icon: "hero-home"},
      %{path: "/lockers", label: "Lockers", icon: "hero-archive-box"},
      %{path: "/sessions", label: "Sessions", icon: "hero-clock"},
      %{path: "/nodes", label: "Node Config", icon: "hero-server"}
    ]
  end

  def settings_schema do
    [
      %{
        key: :allow_self_release,
        type: :boolean,
        label: "Allow Self-Release",
        default: true,
        description: "Allow visitors to release their own locker from the check-out screen"
      },
      %{
        key: :auto_expire_hours,
        type: :integer,
        label: "Auto-Expire After (hours)",
        default: 24,
        description:
          "Automatically mark locker sessions as expired after this many hours. Set to 0 to disable."
      },
      %{
        key: :show_locker_number_on_receipt,
        type: :boolean,
        label: "Show Locker Number on Receipt",
        default: true,
        description: "Display the assigned locker number on the visitor check-in receipt"
      },
      %{
        key: :notify_on_expiry,
        type: :boolean,
        label: "Notify Staff on Expiry",
        default: false,
        description: "Send a dashboard notification when a locker session expires"
      }
    ]
  end

  # ── Hook Handlers ─────────────────────────────────────────────────────────────

  @doc """
  Hook handler for `:visitor_check_in_panels`.

  Receives a payload map from the core check-in LiveView after a successful
  check-in. If this node has lockers available, appends a
  `{VoileLockerLuggage.CheckInPanel, assigns}` entry to `payload.panels` and
  sets `payload.auto_close_ms` to 30 000 so the modal stays open long enough
  for the visitor to respond.

  Returns the payload unchanged if lockers are not enabled or unavailable.
  """
  @spec check_in_panels_hook(map()) :: map()
  def check_in_panels_hook(
        %{panels: panels, node_id: node_id, visitor_log: visitor_log, visitor_name: visitor_name, visitor_identifier: visitor_identifier} =
          payload
      ) do
    location_id = Map.get(payload, :location_id)

    if VoileLockerLuggage.Lockers.node_enabled?(node_id) do
      count =
        if location_id do
          VoileLockerLuggage.Lockers.list_available_lockers_for_location(location_id) |> length()
        else
          VoileLockerLuggage.Lockers.list_available_lockers(node_id) |> length()
        end

      if count > 0 and not panel_already_present?(panels, VoileLockerLuggage.CheckInPanel) do
        panel_assigns = %{
          id: "locker-offer-#{visitor_log.id}",
          node_id: node_id,
          location_id: location_id,
          visitor_log_id: visitor_log.id,
          visitor_identifier: visitor_identifier,
          visitor_name: visitor_name,
          available_count: count
        }

        %{
          payload
          | panels: panels ++ [{VoileLockerLuggage.CheckInPanel, panel_assigns}],
            auto_close_ms: 30_000
        }
      else
        payload
      end
    else
      payload
    end
  rescue
    _ -> payload
  end

  def check_in_panels_hook(payload), do: payload

  defp panel_already_present?(panels, module) do
    Enum.any?(panels, fn
      {existing_module, _assigns} when existing_module == module -> true
      _ -> false
    end)
  end
end
