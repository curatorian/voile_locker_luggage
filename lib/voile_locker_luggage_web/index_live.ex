defmodule VoileLockerLuggage.Web.IndexLive do
  @moduledoc "Plugin dashboard overview — summary stats across all nodes."

  use Phoenix.LiveView
  import Phoenix.Component

  @compile {:no_warn_undefined, [Voile.Schema.System, Voile.Schema.Master, VoileWeb.Auth.Authorization]}

  alias VoileLockerLuggage.Lockers
  alias Voile.Schema.System
  alias VoileLockerLuggageWeb

  @impl true
  def mount(_params, session, socket) do
    socket = VoileLockerLuggageWeb.mount_auth(socket, session)
    is_super_admin = socket.assigns.is_super_admin
    user_node_id = socket.assigns.current_user_node_id

    nodes =
      System.list_nodes()
      |> maybe_filter_nodes(user_node_id, is_super_admin)

    node_summaries =
      Enum.map(nodes, fn node ->
        config = Lockers.get_node_config(node.id)
        enabled = config && config.enabled

        counts = if enabled, do: Lockers.count_lockers_by_status(node.id), else: %{}

        active_sessions =
          if enabled, do: Lockers.list_active_sessions(node.id) |> length(), else: 0

        location_summaries =
          if enabled do
            try do
              Voile.Schema.Master.list_locations(node_id: node.id, is_active: true)
              |> Enum.map(fn location ->
                loc_counts = Lockers.count_lockers_by_status_for_location(location.id)

                %{
                  location_id: location.id,
                  location_name: location.location_name,
                  available: Map.get(loc_counts, "available", 0),
                  occupied: Map.get(loc_counts, "occupied", 0),
                  maintenance: Map.get(loc_counts, "maintenance", 0)
                }
              end)
              |> Enum.filter(fn s -> s.available + s.occupied + s.maintenance > 0 end)
            rescue
              _ -> []
            end
          else
            []
          end

        %{
          node: node,
          config: config,
          enabled: enabled || false,
          counts: counts,
          active_sessions: active_sessions,
          location_summaries: location_summaries
        }
      end)

    {:ok,
     socket
     |> assign(:page_title, "Locker & Luggage")
     |> assign(:node_summaries, node_summaries)
     |> assign(:show_configure_nodes, is_super_admin)}
  end

  defp maybe_filter_nodes(nodes, _user_node_id, true), do: nodes

  defp maybe_filter_nodes(_nodes, nil, false), do: []

  defp maybe_filter_nodes(nodes, user_node_id, false) do
    Enum.filter(nodes, &(&1.id == user_node_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Locker & Luggage</h1>
          <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">Overview of locker usage across all nodes</p>
        </div>
        <%= if @show_configure_nodes do %>
          <a
            href="/manage/plugins/locker_luggage/nodes"
            class="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700"
          >
            ⚙ Configure Nodes
          </a>
        <% end %>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for summary <- @node_summaries do %>
          <div class="bg-white dark:bg-gray-800 rounded-xl shadow border border-gray-100 dark:border-gray-700 p-5">
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="font-semibold text-gray-900 dark:text-white text-lg">
                  {summary.node.name}
                </h2>
                <%= if summary.node.abbr do %>
                  <span class="text-xs text-gray-400">{summary.node.abbr}</span>
                <% end %>
              </div>
              <%= if summary.enabled do %>
                <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-200">
                  Enabled
                </span>
              <% else %>
                <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                  Disabled
                </span>
              <% end %>
            </div>

            <%= if summary.enabled do %>
              <div class="grid grid-cols-3 gap-3 mb-4">
                <div class="text-center">
                  <div class="text-2xl font-bold text-green-600">
                    {Map.get(summary.counts, "available", 0)}
                  </div>
                  <div class="text-xs text-gray-500">Available</div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-bold text-red-600">
                    {Map.get(summary.counts, "occupied", 0)}
                  </div>
                  <div class="text-xs text-gray-500">Occupied</div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-bold text-yellow-600">
                    {Map.get(summary.counts, "maintenance", 0)}
                  </div>
                  <div class="text-xs text-gray-500">Maintenance</div>
                </div>
              </div>
              <div class="flex gap-2">
                <a
                  href={"/manage/plugins/locker_luggage/lockers?node_id=#{summary.node.id}"}
                  class="flex-1 text-center py-1.5 text-xs font-medium text-indigo-600 border border-indigo-200 rounded-lg hover:bg-indigo-50"
                >
                  Manage Lockers
                </a>
                <a
                  href={"/manage/plugins/locker_luggage/sessions?node_id=#{summary.node.id}"}
                  class="flex-1 text-center py-1.5 text-xs font-medium text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 dark:bg-gray-900 dark:text-gray-300 dark:border-gray-700 dark:hover:bg-gray-800"
                >
                  Sessions
                </a>
              </div>

              <%!-- Per-location breakdown --%>
              <%= if summary.location_summaries != [] do %>
                <div class="mt-4 pt-4 border-t border-gray-100 dark:border-gray-700 space-y-1.5">
                  <p class="text-xs font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wide mb-2">
                    By Location
                  </p>
                  <%= for loc <- summary.location_summaries do %>
                    <div class="flex items-center justify-between text-xs">
                      <span class="text-gray-600 dark:text-gray-400 truncate flex-1 mr-2">
                        {loc.location_name}
                      </span>
                      <div class="flex gap-2 shrink-0">
                        <span class="text-green-600 dark:text-green-400 font-medium">
                          {loc.available} avail
                        </span>
                        <span class="text-red-500 dark:text-red-400 font-medium">
                          {loc.occupied} occ
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% else %>
              <p class="text-sm text-gray-400 text-center py-4">
                Locker system not enabled for this node
              </p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
