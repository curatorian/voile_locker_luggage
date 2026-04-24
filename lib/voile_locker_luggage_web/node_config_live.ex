defmodule VoileLockerLuggage.Web.NodeConfigLive do
  @moduledoc """
  Node configuration LiveView.
  Allows admins to enable/disable the locker system per node and set the locker count.
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @compile {:no_warn_undefined, [Voile.Schema.System, Voile.Schema.Master, VoileWeb.Auth.Authorization]}

  alias VoileLockerLuggage.Lockers
  alias VoileLockerLuggage.LockerNodeConfig
  alias VoileLockerLuggage.LockerLocationConfig
  alias Voile.Schema.System
  alias VoileLockerLuggageWeb

  @impl true
  def mount(_params, session, socket) do
    socket = VoileLockerLuggageWeb.mount_auth(socket, session)

    if socket.assigns.is_super_admin do
      nodes = System.list_nodes()

      node_configs =
        Enum.map(nodes, fn node ->
          config = Lockers.get_node_config(node.id)
          {node, config}
        end)

      location_configs_map = build_location_configs_map(nodes)

      {:ok,
       socket
       |> assign(:page_title, "Node Locker Configuration")
       |> assign(:node_configs, node_configs)
       |> assign(:location_configs_map, location_configs_map)
       |> assign(:editing_node_id, nil)
       |> assign(:form, nil)
       |> assign(:expanded_node_id, nil)
       |> assign(:editing_location_id, nil)
       |> assign(:location_form, nil)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Node Locker Configuration")
       |> assign(:node_configs, [])
       |> assign(:location_configs_map, %{})
       |> assign(:editing_node_id, nil)
       |> assign(:form, nil)
       |> assign(:expanded_node_id, nil)
       |> assign(:editing_location_id, nil)
       |> assign(:location_form, nil)
       |> put_flash(:error, "Access denied. Super admin only.")
       |> push_navigate(to: "/manage/plugins/locker_luggage/")}
    end
  end

  @impl true
  def handle_event("edit_node", %{"node_id" => node_id_str}, socket) do
    if socket.assigns.is_super_admin do
      node_id = String.to_integer(node_id_str)
      config = Lockers.get_node_config(node_id)

      attrs =
        if config do
          %{
            enabled: config.enabled,
            total_lockers: config.total_lockers,
            max_duration_hours: config.max_duration_hours,
            notes: config.notes || ""
          }
        else
          %{enabled: false, total_lockers: 50, max_duration_hours: 8, notes: ""}
        end

      changeset =
        (config || %LockerNodeConfig{})
        |> LockerNodeConfig.changeset(attrs)

      {:noreply,
       socket
       |> assign(:editing_node_id, node_id)
       |> assign(:form, to_form(changeset, as: :node_config))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_node_id, nil) |> assign(:form, nil)}
  end

  @impl true
  def handle_event("toggle_locations", %{"node_id" => node_id_str}, socket) do
    node_id = String.to_integer(node_id_str)

    expanded =
      if socket.assigns.expanded_node_id == node_id, do: nil, else: node_id

    {:noreply,
     socket
     |> assign(:expanded_node_id, expanded)
     |> assign(:editing_location_id, nil)
     |> assign(:location_form, nil)}
  end

  @impl true
  def handle_event(
        "edit_location_config",
        %{"location_id" => location_id_str, "node_id" => node_id_str},
        socket
      ) do
    if socket.assigns.is_super_admin do
      location_id = String.to_integer(location_id_str)
      node_id = String.to_integer(node_id_str)
      config = Lockers.get_location_config(location_id)

      attrs =
        if config do
          %{
            enabled: config.enabled,
            total_lockers: config.total_lockers,
            notes: config.notes || ""
          }
        else
          %{enabled: true, total_lockers: 10, notes: ""}
        end

      changeset =
        (config || %LockerLocationConfig{})
        |> LockerLocationConfig.changeset(
          Map.merge(attrs, %{location_id: location_id, node_id: node_id})
        )

      {:noreply,
       socket
       |> assign(:editing_location_id, location_id)
       |> assign(:location_form, to_form(changeset, as: :location_config))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit_location", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_location_id, nil)
     |> assign(:location_form, nil)}
  end

  @impl true
  def handle_event("save_location_config", %{"location_config" => params}, socket) do
    if socket.assigns.is_super_admin do
      location_id = socket.assigns.editing_location_id

      node_id =
        socket.assigns.location_configs_map
        |> Enum.find_value(fn {nid, locs} ->
          if Enum.any?(locs, fn {loc, _} -> loc.id == location_id end), do: nid
        end)

      attrs = %{
        enabled: params["enabled"] == "true",
        total_lockers: String.to_integer(params["total_lockers"] || "10"),
        notes: params["notes"]
      }

      case Lockers.upsert_location_config(location_id, node_id, attrs) do
        {:ok, _config} ->
          if attrs.enabled do
            Lockers.sync_lockers_for_location(location_id, node_id, attrs.total_lockers)
          end

          nodes = System.list_nodes()

          {:noreply,
           socket
           |> assign(:location_configs_map, build_location_configs_map(nodes))
           |> assign(:editing_location_id, nil)
           |> assign(:location_form, nil)
           |> put_flash(:info, "Location configuration saved.")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:location_form, to_form(changeset, as: :location_config))
           |> put_flash(:error, "Failed to save location configuration.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_config", %{"node_config" => params}, socket) do
    if socket.assigns.is_super_admin do
      node_id = socket.assigns.editing_node_id

      attrs = %{
        enabled: params["enabled"] == "true",
        total_lockers: String.to_integer(params["total_lockers"] || "50"),
        max_duration_hours: String.to_integer(params["max_duration_hours"] || "8"),
        notes: params["notes"]
      }

      case Lockers.upsert_node_config(node_id, attrs) do
        {:ok, _config} ->
          if attrs.enabled do
            Lockers.sync_lockers_for_node(node_id, attrs.total_lockers)
          end

          nodes = System.list_nodes()

          node_configs =
            Enum.map(nodes, fn node ->
              {node, Lockers.get_node_config(node.id)}
            end)

          {:noreply,
           socket
           |> assign(:node_configs, node_configs)
           |> assign(:location_configs_map, build_location_configs_map(nodes))
           |> assign(:editing_node_id, nil)
           |> assign(:form, nil)
           |> put_flash(:info, "Node configuration saved.")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:form, to_form(changeset, as: :node_config))
           |> put_flash(:error, "Failed to save configuration.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl mx-auto">
      <div class="mb-6 flex items-center gap-4">
        <.link
          navigate="/manage/plugins/locker_luggage/"
          class="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-white text-lg font-bold"
        >
          &larr;
        </.link>
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
            Node Locker Configuration
          </h1>
          <p class="text-sm text-gray-500 mt-1">
            Enable or disable the locker system per node and configure locker counts.
          </p>
        </div>
      </div>

      <div class="space-y-4">
        <%= if !@is_super_admin do %>
          <div class="bg-red-50 dark:bg-red-900/20 rounded-xl border border-red-200 dark:border-red-700 p-8 text-center">
            <p class="text-lg font-semibold text-red-700 dark:text-red-200">Unauthorized</p>
            <p class="text-sm text-red-600 dark:text-red-300 mt-2">
              You do not have permission to access node configuration.
            </p>
          </div>
        <% else %>
          <%= for {node, config} <- @node_configs do %>
            <div class="bg-white dark:bg-gray-800 rounded-xl shadow border border-gray-100 dark:border-gray-700 p-5">
            <%= if @editing_node_id == node.id do %>
              <h2 class="font-semibold text-gray-900 dark:text-white mb-4">
                Configuring: {node.name}
              </h2>
              <.form
                for={@form}
                id={"node-config-form-#{node.id}"}
                phx-submit="save_config"
                class="space-y-4"
              >
                <div class="flex items-center gap-3">
                  <label class="text-sm font-medium text-gray-700 dark:text-gray-300">
                    Enable locker system for this node
                  </label>
                  <select
                    name="node_config[enabled]"
                    class="border border-gray-300 rounded-lg px-3 py-1.5 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option
                      value="true"
                      selected={Ecto.Changeset.get_field(@form.source, :enabled) == true}
                    >
                      Enabled
                    </option>
                    <option
                      value="false"
                      selected={Ecto.Changeset.get_field(@form.source, :enabled) == false}
                    >
                      Disabled
                    </option>
                  </select>
                </div>

                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                      Total Lockers
                    </label>
                    <input
                      type="number"
                      name="node_config[total_lockers]"
                      value={Ecto.Changeset.get_field(@form.source, :total_lockers)}
                      min="1"
                      class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                      Max Duration (hours)
                    </label>
                    <input
                      type="number"
                      name="node_config[max_duration_hours]"
                      value={Ecto.Changeset.get_field(@form.source, :max_duration_hours)}
                      min="1"
                      class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Notes (optional)
                  </label>
                  <textarea
                    name="node_config[notes]"
                    rows="2"
                    class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >{Ecto.Changeset.get_field(@form.source, :notes)}</textarea>
                </div>

                <div class="flex gap-3">
                  <button
                    type="submit"
                    class="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="px-4 py-2 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            <% else %>
              <div class="flex items-center justify-between">
                <div>
                  <h6 class="font-semibold text-gray-900 dark:text-white">{node.name}</h6>
                  <%= if node.abbr do %>
                    <span class="text-xs text-gray-400">{node.abbr}</span>
                  <% end %>
                  <%= if config do %>
                    <div class="mt-1 flex items-center gap-3 text-sm text-gray-500 dark:text-gray-400">
                      <span>Lockers: {config.total_lockers}</span>
                      <span>Max: {config.max_duration_hours}h</span>
                      <%= if config.notes && config.notes != "" do %>
                        <span class="italic">{config.notes}</span>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="text-sm text-gray-400 mt-1">Not configured</p>
                  <% end %>
                </div>
                <div class="flex items-center gap-2">
                  <.status_badge config={config} />
                  <button
                    phx-click="toggle_locations"
                    phx-value-node_id={node.id}
                    class="px-3 py-1.5 text-sm font-medium text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-700"
                  >
                    {if @expanded_node_id == node.id, do: "Hide Locations", else: "Locations"}
                  </button>
                  <button
                    phx-click="edit_node"
                    phx-value-node_id={node.id}
                    class="px-3 py-1.5 text-sm font-medium text-indigo-600 border border-indigo-200 rounded-lg hover:bg-indigo-50 dark:text-indigo-200 dark:border-indigo-700 dark:hover:bg-indigo-700/20"
                  >
                    Configure
                  </button>
                </div>
              </div>

              <%!-- Per-location configuration (expandable) --%>
              <%= if @expanded_node_id == node.id do %>
                <% loc_entries = Map.get(@location_configs_map, node.id, []) %>
                <div class="mt-4 pt-4 border-t border-gray-100 dark:border-gray-700">
                  <p class="text-xs font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wide mb-3">
                    Location Configuration
                  </p>
                  <%= if loc_entries == [] do %>
                    <p class="text-sm text-gray-400 italic">
                      No active locations found for this node.
                    </p>
                  <% else %>
                    <div class="space-y-3">
                      <%= for {location, loc_config} <- loc_entries do %>
                        <div class="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
                          <%= if @editing_location_id == location.id do %>
                            <p class="font-medium text-gray-800 dark:text-gray-200 mb-3">
                              {location.location_name}
                            </p>
                            <.form
                              for={@location_form}
                              id={"location-config-form-#{location.id}"}
                              phx-submit="save_location_config"
                              class="space-y-3"
                            >
                              <div class="flex items-center gap-3">
                                <label class="text-sm font-medium text-gray-700 dark:text-gray-300">
                                  Enable lockers for this location
                                </label>
                                <select
                                  name="location_config[enabled]"
                                  class="border border-gray-300 rounded-lg px-3 py-1.5 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                                >
                                  <option
                                    value="true"
                                    selected={Ecto.Changeset.get_field(@location_form.source, :enabled) == true}
                                  >
                                    Enabled
                                  </option>
                                  <option
                                    value="false"
                                    selected={Ecto.Changeset.get_field(@location_form.source, :enabled) == false}
                                  >
                                    Disabled
                                  </option>
                                </select>
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                  Total Lockers
                                </label>
                                <input
                                  type="number"
                                  name="location_config[total_lockers]"
                                  value={Ecto.Changeset.get_field(@location_form.source, :total_lockers)}
                                  min="1"
                                  class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                                />
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                  Notes (optional)
                                </label>
                                <input
                                  type="text"
                                  name="location_config[notes]"
                                  value={Ecto.Changeset.get_field(@location_form.source, :notes)}
                                  class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                                />
                              </div>
                              <div class="flex gap-2">
                                <button
                                  type="submit"
                                  class="px-3 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
                                >
                                  Save
                                </button>
                                <button
                                  type="button"
                                  phx-click="cancel_edit_location"
                                  class="px-3 py-1.5 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                                >
                                  Cancel
                                </button>
                              </div>
                            </.form>
                          <% else %>
                            <div class="flex items-center justify-between">
                              <div>
                                <p class="text-sm font-medium text-gray-800 dark:text-gray-200">
                                  {location.location_name}
                                </p>
                                <%= if loc_config do %>
                                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                                    {loc_config.total_lockers} lockers
                                    <%= if loc_config.notes && loc_config.notes != "" do %>
                                      &middot; {loc_config.notes}
                                    <% end %>
                                  </p>
                                <% else %>
                                  <p class="text-xs text-gray-400 mt-0.5">Not configured</p>
                                <% end %>
                              </div>
                              <div class="flex items-center gap-2">
                                <.location_badge config={loc_config} />
                                <button
                                  phx-click="edit_location_config"
                                  phx-value-location_id={location.id}
                                  phx-value-node_id={node.id}
                                  class="px-2 py-1 text-xs font-medium text-indigo-600 border border-indigo-200 rounded hover:bg-indigo-50 dark:text-indigo-300 dark:border-indigo-700 dark:hover:bg-indigo-700/20"
                                >
                                  Configure
                                </button>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
  defp status_badge(assigns) do
    ~H"""
    <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium " <> status_badge_class(@config)}>
      {status_badge_label(@config)}
    </span>
    """
  end

  defp status_badge_class(config) do
    cond do
      config && config.enabled ->
        "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300"

      config && !config.enabled ->
        "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300"

      true ->
        "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-300"
    end
  end

  defp status_badge_label(config) do
    cond do
      config && config.enabled -> "Enabled"
      config && !config.enabled -> "Disabled"
      true -> "Not set"
    end
  end

  defp location_badge(assigns) do
    ~H"""
    <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium " <> location_badge_class(@config)}>
      {location_badge_label(@config)}
    </span>
    """
  end

  defp location_badge_class(config) do
    cond do
      config && config.enabled ->
        "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300"

      config && !config.enabled ->
        "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300"

      true ->
        "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-300"
    end
  end

  defp location_badge_label(config) do
    cond do
      config && config.enabled -> "Enabled"
      config && !config.enabled -> "Disabled"
      true -> "Not set"
    end
  end

  defp build_location_configs_map(nodes) do
    Enum.reduce(nodes, %{}, fn node, acc ->
      locations =
        try do
          Voile.Schema.Master.list_locations(node_id: node.id, is_active: true)
        rescue
          _ -> []
        end

      loc_with_configs =
        Enum.map(locations, fn location ->
          {location, Lockers.get_location_config(location.id)}
        end)

      Map.put(acc, node.id, loc_with_configs)
    end)
  end
end
