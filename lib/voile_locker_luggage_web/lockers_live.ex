defmodule VoileLockerLuggage.Web.LockersLive do
  @moduledoc """
  Locker management LiveView.
  Allows staff to view, add, edit, and manage individual lockers for a node.
  """

  use Phoenix.LiveView

  @compile {:no_warn_undefined, [Voile.Schema.System, Voile.Schema.Master, VoileWeb.Auth.Authorization]}

  alias VoileLockerLuggage.{Lockers, Locker}
  alias Voile.Schema.System
  alias VoileLockerLuggageWeb

  @impl true
  def mount(params, session, socket) do
    socket = VoileLockerLuggageWeb.mount_auth(socket, session)
    is_super_admin = socket.assigns.is_super_admin
    user_node_id = socket.assigns.current_user_node_id

    nodes = System.list_nodes()
    nodes = maybe_filter_nodes(nodes, user_node_id, is_super_admin)
    enabled_nodes = Enum.filter(nodes, fn n -> Lockers.node_enabled?(n.id) end)

    node_id_param = if is_map(params), do: Map.get(params, "node_id"), else: nil

    node_id =
      case node_id_param do
        nil ->
          case enabled_nodes do
            [first | _] -> first.id
            [] -> user_node_id
          end

        id_str ->
          id = String.to_integer(id_str)
          if is_super_admin or id == user_node_id, do: id, else: user_node_id
      end

    {:ok,
     socket
     |> assign(:page_title, "Manage Lockers")
     |> assign(:nodes, enabled_nodes)
     |> assign(:selected_node_id, node_id)
     |> assign(:locations, [])
     |> assign(:location_map, %{})
     |> assign(:selected_location_id, nil)
     |> assign(:show_form, false)
     |> assign(:editing_locker, nil)
     |> assign(:form, nil)
     |> assign(:show_assign_form, false)
     |> assign(:assign_locker_id, nil)
     |> assign(:assign_form, nil)
     |> load_lockers(node_id)}
  end

  defp maybe_filter_nodes(nodes, _user_node_id, true), do: nodes
  defp maybe_filter_nodes(_nodes, nil, false), do: []

  defp maybe_filter_nodes(nodes, user_node_id, false),
    do: Enum.filter(nodes, &(&1.id == user_node_id))

  defp enforce_node_scope(node_id, socket) do
    if socket.assigns.is_super_admin do
      node_id
    else
      if node_id == socket.assigns.current_user_node_id,
        do: node_id,
        else: socket.assigns.current_user_node_id
    end
  end

  defp load_lockers(socket, nil) do
    socket
    |> assign(:lockers, [])
    |> assign(:sessions_by_locker, %{})
    |> assign(:counts, %{})
    |> assign(:locations, [])
    |> assign(:location_map, %{})
  end

  defp load_lockers(socket, node_id) do
    location_id = socket.assigns[:selected_location_id]
    # Active locations only — used for sub-tab filter buttons
    locations = load_locations(node_id, is_active: true)
    # All locations (including inactive) — used to label locker cards
    all_locations = load_locations(node_id)

    {lockers, active_sessions, counts} =
      if location_id do
        {
          Lockers.list_lockers_for_location(location_id),
          Lockers.list_active_sessions_for_location(location_id),
          Lockers.count_lockers_by_status_for_location(location_id)
        }
      else
        {
          Lockers.list_lockers(node_id),
          Lockers.list_active_sessions(node_id),
          Lockers.count_lockers_by_status(node_id)
        }
      end

    sessions_by_locker = Map.new(active_sessions, &{&1.locker_id, &1})
    location_map = Map.new(all_locations, &{&1.id, &1.location_name})

    socket
    |> assign(:lockers, lockers)
    |> assign(:sessions_by_locker, sessions_by_locker)
    |> assign(:counts, counts)
    |> assign(:locations, locations)
    |> assign(:location_map, location_map)
  end

  defp load_locations(nil), do: []
  defp load_locations(node_id), do: load_locations(node_id, [])

  defp load_locations(nil, _opts), do: []
  defp load_locations(node_id, opts) do
    try do
      Voile.Schema.Master.list_locations([{:node_id, node_id} | opts])
    rescue
      _ -> []
    end
  end

  @impl true
  def handle_event("select_node", %{"node_id" => node_id_str}, socket) do
    node_id = String.to_integer(node_id_str)
    node_id = enforce_node_scope(node_id, socket)

    {:noreply,
     socket
     |> assign(:selected_node_id, node_id)
     |> assign(:selected_location_id, nil)
     |> assign(:show_form, false)
     |> assign(:editing_locker, nil)
     |> load_lockers(node_id)}
  end

  @impl true
  def handle_event("select_location", %{"location_id" => "all"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_location_id, nil)
     |> load_lockers(socket.assigns.selected_node_id)}
  end

  @impl true
  def handle_event("select_location", %{"location_id" => location_id_str}, socket) do
    location_id = String.to_integer(location_id_str)

    {:noreply,
     socket
     |> assign(:selected_location_id, location_id)
     |> load_lockers(socket.assigns.selected_node_id)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_lockers(socket, socket.assigns.selected_node_id)}
  end

  @impl true
  def handle_event("new_locker", _params, socket) do
    changeset = Locker.changeset(%Locker{}, %{})

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_locker, nil)
     |> assign(:form, to_form(changeset, as: :locker))}
  end

  @impl true
  def handle_event("edit_locker", %{"id" => id}, socket) do
    locker = Lockers.get_locker!(id)
    changeset = Locker.changeset(locker, %{})

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_locker, locker)
     |> assign(:form, to_form(changeset, as: :locker))}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_locker, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("save_locker", %{"locker" => params}, socket) do
    node_id = socket.assigns.selected_node_id

    attrs =
      params
      |> Map.put("node_id", node_id)
      |> Map.put("status", params["status"] || "available")
      |> then(fn a ->
        case a["location_id"] do
          "" -> Map.put(a, "location_id", nil)
          nil -> Map.put(a, "location_id", nil)
          _ -> a
        end
      end)

    result =
      case socket.assigns.editing_locker do
        nil -> Lockers.create_locker(attrs)
        locker -> Lockers.update_locker(locker, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_locker, nil)
         |> assign(:form, nil)
         |> load_lockers(node_id)
         |> put_flash(:info, "Locker saved.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :locker))
         |> put_flash(:error, "Please fix the errors below.")}
    end
  end

  @impl true
  def handle_event("delete_locker", %{"id" => id}, socket) do
    locker = Lockers.get_locker!(id)

    case Lockers.delete_locker(locker) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_lockers(socket.assigns.selected_node_id)
         |> put_flash(:info, "Locker deleted.")}

      {:error, :has_active_sessions} ->
        {:noreply, put_flash(socket, :error, "Cannot delete locker with active sessions.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete locker.")}
    end
  end

  @impl true
  def handle_event("open_assign", %{"id" => locker_id}, socket) do
    {:noreply,
     socket
     |> assign(:show_assign_form, true)
     |> assign(:assign_locker_id, locker_id)
     |> assign(:assign_form, to_form(%{}, as: :assign))}
  end

  @impl true
  def handle_event("cancel_assign", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_assign_form, false)
     |> assign(:assign_locker_id, nil)
     |> assign(:assign_form, nil)}
  end

  @impl true
  def handle_event("submit_assign", %{"assign" => params}, socket) do
    node_id = socket.assigns.selected_node_id
    locker_id = socket.assigns.assign_locker_id
    identifier = String.trim(params["visitor_identifier"] || "")
    visitor_name = String.trim(params["visitor_name"] || "")

    if identifier == "" do
      {:noreply,
       socket
       |> assign(:assign_form, to_form(%{"visitor_identifier" => ""}, as: :assign))
       |> put_flash(:error, "Visitor identifier is required.")}
    else
      case Lockers.assign_locker(node_id, identifier, visitor_name, locker_id: locker_id) do
        {:ok, _session} ->
          {:noreply,
           socket
           |> assign(:show_assign_form, false)
           |> assign(:assign_locker_id, nil)
           |> assign(:assign_form, nil)
           |> load_lockers(node_id)
           |> put_flash(:info, "Locker assigned to #{identifier}.")}

        {:error, :locker_not_available} ->
          {:noreply, put_flash(socket, :error, "Locker is no longer available.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to assign locker.")}
      end
    end
  end

  @impl true
  def handle_event("release_locker", %{"session_id" => session_id}, socket) do
    node_id = socket.assigns.selected_node_id

    case Lockers.release_locker(session_id,
           release_method: "staff_manual",
           released_by: staff_email(socket)
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_lockers(node_id)
         |> put_flash(:info, "Locker released.")}

      {:error, :already_released} ->
        {:noreply, put_flash(socket, :error, "This locker is already released.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to release locker.")}
    end
  end

  @impl true
  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    locker = Lockers.get_locker!(id)

    case Lockers.update_locker(locker, %{status: status}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_lockers(socket.assigns.selected_node_id)
         |> put_flash(:info, "Locker status updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="mb-6 flex items-center gap-4">
        <.link
          navigate="/manage/plugins/locker_luggage/"
          class="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-white text-lg font-bold"
        >
          &larr;
        </.link>
        <div class="flex-1">
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Manage Lockers</h1>
        </div>
        <%= if @selected_node_id do %>
          <button
            phx-click="refresh"
            class="inline-flex items-center gap-2 px-4 py-2 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
          >
            Refresh
          </button>
        <% end %>
        <%= if @selected_node_id && @is_super_admin do %>
          <button
            phx-click="new_locker"
            class="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
          >
            + Add Locker
          </button>
        <% end %>
      </div>

      <%!-- Node selector --%>
      <%= if @nodes != [] do %>
        <div class="flex flex-wrap gap-2 mb-3">
          <%= for node <- @nodes do %>
            <button
              phx-click="select_node"
              phx-value-node_id={node.id}
              class={[
                "px-4 py-2 text-sm font-medium rounded-lg border transition-colors",
                if(@selected_node_id == node.id,
                  do: "bg-indigo-600 text-white border-indigo-600",
                  else:
                    "bg-white text-gray-700 border-gray-200 hover:bg-gray-50 dark:bg-gray-900 dark:text-gray-300 dark:border-gray-700 dark:hover:bg-gray-800"
                )
              ]}
            >
              {node.name}
            </button>
          <% end %>
        </div>
      <% end %>

      <%!-- Location sub-tabs (visible when a node is selected and has locations) --%>
      <%= if @selected_node_id && @locations != [] do %>
        <div class="flex flex-wrap gap-1.5 mb-6 pl-3 border-l-4 border-indigo-200 dark:border-indigo-700">
          <button
            phx-click="select_location"
            phx-value-location_id="all"
            class={[
              "px-3 py-1 text-xs font-medium rounded-md border transition-colors",
              if(is_nil(@selected_location_id),
                do:
                  "bg-indigo-100 text-indigo-700 border-indigo-300 dark:bg-indigo-900/40 dark:text-indigo-300 dark:border-indigo-600",
                else:
                  "bg-white text-gray-500 border-gray-200 hover:bg-gray-50 dark:bg-gray-900 dark:text-gray-400 dark:border-gray-700 dark:hover:bg-gray-800"
              )
            ]}
          >
            All Locations
          </button>
          <%= for location <- @locations do %>
            <button
              phx-click="select_location"
              phx-value-location_id={location.id}
              class={[
                "px-3 py-1 text-xs font-medium rounded-md border transition-colors",
                if(@selected_location_id == location.id,
                  do:
                    "bg-indigo-100 text-indigo-700 border-indigo-300 dark:bg-indigo-900/40 dark:text-indigo-300 dark:border-indigo-600",
                  else:
                    "bg-white text-gray-500 border-gray-200 hover:bg-gray-50 dark:bg-gray-900 dark:text-gray-400 dark:border-gray-700 dark:hover:bg-gray-800"
                )
              ]}
            >
              {location.location_name}
            </button>
          <% end %>
        </div>
      <% end %>

      <%!-- Stats row --%>
      <%= if @selected_node_id do %>
        <div class="grid grid-cols-4 gap-4 mb-6">
          <%= for {status, label, color} <- [{"available", "Available", "green"}, {"occupied", "Occupied", "red"}, {"maintenance", "Maintenance", "yellow"}, {"reserved", "Reserved", "blue"}] do %>
            <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-100 dark:border-gray-700 p-4 text-center">
              <div class={"text-2xl font-bold text-#{color}-600"}>
                {Map.get(@counts, status, 0)}
              </div>
              <div class="text-xs text-gray-500 mt-0.5">{label}</div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- New/Edit form --%>
      <%= if @show_form do %>
        <div class="bg-white dark:bg-gray-800 rounded-xl shadow border border-gray-100 dark:border-gray-700 p-5 mb-6">
          <h2 class="font-semibold text-gray-900 dark:text-white mb-4">
            {if @editing_locker, do: "Edit Locker", else: "New Locker"}
          </h2>
          <.form
            for={@form}
            id="locker-form"
            phx-submit="save_locker"
            class="grid grid-cols-3 gap-4"
          >
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Locker Number
              </label>
              <input
                type="text"
                name="locker[locker_number]"
                value={Ecto.Changeset.get_field(@form.source, :locker_number)}
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Location
              </label>
              <select
                name="locker[location_id]"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              >
                <option value="">— No location —</option>
                <%= for location <- @locations do %>
                  <option
                    value={location.id}
                    selected={Ecto.Changeset.get_field(@form.source, :location_id) == location.id}
                  >
                    {location.location_name}
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Status
              </label>
              <select
                name="locker[status]"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              >
                <%= for s <- VoileLockerLuggage.Locker.statuses() do %>
                  <option
                    value={s}
                    selected={Ecto.Changeset.get_field(@form.source, :status) == s}
                  >
                    {String.capitalize(s)}
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Notes (optional)
              </label>
              <input
                type="text"
                name="locker[notes]"
                value={Ecto.Changeset.get_field(@form.source, :notes)}
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div class="col-span-3 flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel_form"
                class="px-4 py-2 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              >
                Cancel
              </button>
            </div>
          </.form>
        </div>
      <% end %>

      <%!-- Manual assign form --%>
      <%= if @show_assign_form do %>
        <div class="bg-blue-50 dark:bg-blue-900/20 rounded-xl border border-blue-200 dark:border-blue-700 p-5 mb-6">
          <h2 class="font-semibold text-blue-900 dark:text-blue-100 mb-4">
            Manually Assign Locker
          </h2>
          <form phx-submit="submit_assign" id="assign-form" class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Visitor Identifier
              </label>
              <input
                type="text"
                name="assign[visitor_identifier]"
                placeholder="e.g. 2021001234"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Visitor Name (optional)
              </label>
              <input
                type="text"
                name="assign[visitor_name]"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <div class="col-span-2 flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700"
              >
                Assign
              </button>
              <button
                type="button"
                phx-click="cancel_assign"
                class="px-4 py-2 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <%!-- Locker grid --%>
      <%= if @selected_node_id && @lockers != [] do %>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
          <%= for locker <- @lockers do %>
            <% session = Map.get(@sessions_by_locker, locker.id) %>
            <% location_name = if locker.location_id, do: Map.get(@location_map, locker.location_id), else: nil %>
            <div class={[
              "relative rounded-xl border-2 p-3 text-center transition-colors",
              status_card_class(locker.status)
            ]}>
              <div class="text-lg font-bold">{locker.locker_number}</div>
              <%= if location_name do %>
                <div class="text-xs font-medium text-indigo-600 dark:text-indigo-400 truncate" title={location_name}>
                  {location_name}
                </div>
              <% end %>
              <div class="text-xs mt-0.5 capitalize">{locker.status}</div>

              <%= if session do %>
                <%= if session.visitor_name && session.visitor_name != "" do %>
                  <div class="text-sm font-medium mt-1 truncate" title={session.visitor_name}>
                    {session.visitor_name}
                  </div>
                <% end %>
                <div class="text-xs text-gray-600 dark:text-gray-400 mt-0.5 truncate font-mono" title={session.visitor_identifier}>
                  {session.visitor_identifier}
                </div>
              <% end %>

              <div class="mt-2 flex flex-col gap-1">
                <%= cond do %>
                  <% locker.status == "available" -> %>
                    <button
                      phx-click="open_assign"
                      phx-value-id={locker.id}
                      class="text-xs px-2 py-0.5 bg-white border border-blue-300 text-blue-700 rounded hover:bg-blue-50 dark:bg-gray-700 dark:border-blue-600 dark:text-blue-100 dark:hover:bg-blue-600"
                    >
                      Assign
                    </button>
                  <% locker.status == "occupied" && session -> %>
                    <button
                      phx-click="release_locker"
                      phx-value-session_id={session.id}
                      data-confirm={"Release locker #{locker.locker_number}?"}
                      class="text-xs px-2 py-0.5 bg-white border border-red-300 text-red-700 rounded hover:bg-red-50 dark:bg-gray-700 dark:border-red-600 dark:text-red-200 dark:hover:bg-red-600"
                    >
                      Release
                    </button>
                  <% true -> %>
                <% end %>

                <div class="flex gap-1">
                  <button
                    phx-click="edit_locker"
                    phx-value-id={locker.id}
                    class="flex-1 text-xs px-1 py-0.5 bg-white border border-gray-200 text-gray-600 rounded hover:bg-gray-50 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-700"
                  >
                    Edit
                  </button>
                </div>

                <%= if locker.status != "maintenance" do %>
                  <button
                    phx-click="set_status"
                    phx-value-id={locker.id}
                    phx-value-status="maintenance"
                    class="text-xs px-2 py-0.5 bg-white border border-yellow-300 text-yellow-700 rounded hover:bg-yellow-50 dark:bg-gray-700 dark:border-yellow-500 dark:text-yellow-200 dark:hover:bg-yellow-600"
                  >
                    Maintenance
                  </button>
                <% else %>
                  <button
                    phx-click="set_status"
                    phx-value-id={locker.id}
                    phx-value-status="available"
                    class="text-xs px-2 py-0.5 bg-white border border-green-300 text-green-700 rounded hover:bg-green-50 dark:bg-gray-700 dark:border-green-500 dark:text-green-200 dark:hover:bg-green-600"
                  >
                    Re-enable
                  </button>
                <% end %>
                <%= if @is_super_admin do %>
                  <button
                    phx-click="delete_locker"
                    phx-value-id={locker.id}
                    data-confirm={"Delete locker #{locker.locker_number}? This cannot be undone."}
                    class="text-xs px-2 py-0.5 bg-white border border-red-200 text-red-500 rounded hover:bg-red-50 dark:bg-gray-700 dark:border-red-700 dark:text-red-400 dark:hover:bg-red-900/30"
                  >
                    Delete
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @nodes == [] do %>
        <div class="text-center py-20 text-gray-400 dark:text-gray-500">
          <p class="text-4xl mb-4">🗄️</p>
          <p class="text-lg font-semibold text-gray-600 dark:text-gray-300">
            Locker system is not enabled for your node
          </p>
          <p class="text-sm mt-2 max-w-sm mx-auto">
            Please contact your system administrator (super admin) to enable and configure the locker system for your node.
          </p>
          <%= if @is_super_admin do %>
            <.link
              navigate="/manage/plugins/locker_luggage/nodes"
              class="mt-4 inline-block px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
            >
              ⚙ Configure Nodes
            </.link>
          <% end %>
        </div>
      <% end %>

      <%= if @selected_node_id && @lockers == [] do %>
        <div class="text-center py-16 text-gray-400 dark:text-gray-400">
          <p class="text-4xl mb-3">🗄️</p>
          <p class="text-lg font-medium">No lockers configured yet.</p>
          <%= if @is_super_admin do %>
            <p class="text-sm mt-1">
              You can add them manually or set the count in
              <.link
                navigate="/manage/plugins/locker_luggage/nodes"
                class="text-indigo-600 hover:underline"
              >
                node configuration
              </.link>
              to auto-generate.
            </p>
          <% else %>
            <p class="text-sm mt-1">
              Please contact your system administrator (super admin) to set up lockers for this node.
            </p>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_card_class("available"),
    do: "border-green-300 bg-green-50 text-green-900"

  defp status_card_class("occupied"),
    do: "border-red-300 bg-red-50 text-red-900"

  defp status_card_class("maintenance"),
    do: "border-yellow-300 bg-yellow-50 text-yellow-900"

  defp status_card_class("reserved"),
    do:
      "border-blue-300 bg-blue-50 dark:border-blue-600 dark:bg-blue-900/20 dark:text-blue-100 text-blue-900"

  defp status_card_class(_),
    do:
      "border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 text-gray-700"

  defp staff_email(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{email: email}} -> email
      _ -> "staff"
    end
  end
end
