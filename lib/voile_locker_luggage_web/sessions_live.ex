defmodule VoileLockerLuggage.Web.SessionsLive do
  @moduledoc """
  Locker session history LiveView.
  Shows active and historical locker sessions for a node with release capability.
  """

  use Phoenix.LiveView

  @compile {:no_warn_undefined, [Voile.Schema.System, VoileWeb.Auth.Authorization]}

  alias VoileLockerLuggage.Lockers
  alias Voile.Schema.System
  alias VoileLockerLuggageWeb

  @page_size 20

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

    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, "Locker Sessions")
     |> assign(:nodes, enabled_nodes)
     |> assign(:selected_node_id, node_id)
     |> assign(:filter, :active)
     |> assign(:selected_date, today)
     |> assign(:page, 1)
     |> assign(:per_page, @page_size)
     |> assign(:has_next_page, false)
     |> load_sessions(node_id, :active, today)}
  end

  defp maybe_filter_nodes(nodes, _user_node_id, true), do: nodes
  defp maybe_filter_nodes(_nodes, nil, false), do: []
  defp maybe_filter_nodes(nodes, user_node_id, false), do: Enum.filter(nodes, &(&1.id == user_node_id))

  defp enforce_node_scope(node_id, socket) do
    if socket.assigns.is_super_admin do
      node_id
    else
      if node_id == socket.assigns.current_user_node_id, do: node_id, else: socket.assigns.current_user_node_id
    end
  end

  defp load_sessions(socket, nil, _filter, _date) do
    socket
    |> assign(:sessions, [])
    |> assign(:has_next_page, false)
    |> assign(:page, socket.assigns[:page] || 1)
    |> assign(:per_page, socket.assigns[:per_page] || @page_size)
  end

  defp load_sessions(socket, node_id, :active, _date) do
    page = socket.assigns[:page] || 1
    per_page = socket.assigns[:per_page] || @page_size

    {sessions, has_next_page} = Lockers.list_active_sessions(node_id, page, per_page)

    socket
    |> assign(:sessions, sessions)
    |> assign(:has_next_page, has_next_page)
    |> assign(:page, page)
    |> assign(:per_page, per_page)
  end

  defp load_sessions(socket, node_id, :history, nil) do
    page = socket.assigns[:page] || 1
    per_page = socket.assigns[:per_page] || @page_size

    {sessions, has_next_page} = Lockers.list_sessions(node_id, nil, page, per_page)

    socket
    |> assign(:sessions, sessions)
    |> assign(:has_next_page, has_next_page)
    |> assign(:page, page)
    |> assign(:per_page, per_page)
  end

  defp load_sessions(socket, node_id, :history, date) do
    page = socket.assigns[:page] || 1
    per_page = socket.assigns[:per_page] || @page_size

    {sessions, has_next_page} = Lockers.list_sessions(node_id, date, page, per_page)

    socket
    |> assign(:sessions, sessions)
    |> assign(:has_next_page, has_next_page)
    |> assign(:page, page)
    |> assign(:per_page, per_page)
  end

  @impl true
  def handle_event("select_node", %{"node_id" => node_id_str}, socket) do
    node_id = String.to_integer(node_id_str)
    node_id = enforce_node_scope(node_id, socket)

    {:noreply,
     socket
     |> assign(:selected_node_id, node_id)
     |> assign(:page, 1)
     |> load_sessions(node_id, socket.assigns.filter, socket.assigns.selected_date)}
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter_atom = String.to_existing_atom(filter)

    # When switching to history, reset to today so sessions show immediately.
    # When switching to active, date is irrelevant.
    date =
      case filter_atom do
        :history -> Date.utc_today()
        _ -> socket.assigns.selected_date
      end

    {:noreply,
     socket
     |> assign(:filter, filter_atom)
     |> assign(:selected_date, date)
     |> assign(:page, 1)
     |> load_sessions(socket.assigns.selected_node_id, filter_atom, date)}
  end

  def handle_event("set_date", %{"date" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_date, nil)
     |> assign(:page, 1)
     |> load_sessions(socket.assigns.selected_node_id, socket.assigns.filter, nil)}
  end

  def handle_event("set_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:noreply,
         socket
         |> assign(:selected_date, date)
         |> load_sessions(socket.assigns.selected_node_id, socket.assigns.filter, date)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> load_sessions(socket.assigns.selected_node_id, socket.assigns.filter, socket.assigns.selected_date)}
  end

  @impl true
  def handle_event("change_page", %{"direction" => direction}, socket) do
    current_page = socket.assigns[:page] || 1

    page =
      case direction do
        "next" -> current_page + 1
        "prev" -> max(current_page - 1, 1)
        _ -> current_page
      end

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_sessions(socket.assigns.selected_node_id, socket.assigns.filter, socket.assigns.selected_date)}
  end

  @impl true
  def handle_event("release_session", %{"id" => session_id}, socket) do
    case Lockers.release_locker(session_id,
           release_method: "staff_manual",
           released_by: staff_email(socket)
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_sessions(
           socket.assigns.selected_node_id,
           socket.assigns.filter,
           socket.assigns.selected_date
         )
         |> put_flash(:info, "Locker released.")}

      {:error, :already_released} ->
        {:noreply, put_flash(socket, :error, "This session is already closed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to release locker.")}
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
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Locker Sessions</h1>
      </div>

      <%!-- Node tabs --%>
      <%= if @nodes != [] do %>
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for node <- @nodes do %>
            <button
              phx-click="select_node"
              phx-value-node_id={node.id}
              class={[
                "px-4 py-2 text-sm font-medium rounded-lg border transition-colors",
                if(@selected_node_id == node.id,
                  do: "bg-indigo-600 text-white border-indigo-600",
                  else: "bg-white text-gray-700 border-gray-200 hover:bg-gray-50 dark:bg-gray-900 dark:text-gray-300 dark:border-gray-700 dark:hover:bg-gray-800"
                )
              ]}
            >
              {node.name}
            </button>
          <% end %>
        </div>
      <% end %>

      <%!-- Filter bar --%>
      <div class="flex items-center gap-4 mb-6">
        <div class="flex gap-1 bg-gray-100 dark:bg-gray-700 rounded-lg p-1">
          <%= for {label, value} <- [{"Active", "active"}, {"History", "history"}] do %>
            <button
              phx-click="set_filter"
              phx-value-filter={value}
              class={[
                "px-4 py-1.5 text-sm font-medium rounded-md transition-colors",
                if(to_string(@filter) == value,
                  do: "bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm",
                  else: "text-gray-600 dark:text-gray-300 hover:text-gray-800 dark:hover:text-white"
                )
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>

        <button
          phx-click="refresh"
          class="px-4 py-1.5 text-sm font-medium rounded-md border border-gray-200 bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800"
        >
          Refresh
        </button>

        <%= if @filter == :history do %>
          <form phx-change="set_date" id="session-date-filter">
            <input
              type="date"
              value={if @selected_date, do: Date.to_iso8601(@selected_date), else: ""}
              name="date"
              class="border border-gray-300 rounded-lg px-3 py-1.5 text-sm bg-white text-gray-900 dark:bg-gray-900 dark:border-gray-600 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </form>
        <% end %>
      </div>

      <%= if @page > 1 or @has_next_page do %>
        <div class="flex items-center justify-between gap-4 mb-6">
          <div class="text-sm text-gray-600 dark:text-gray-400">Page {@page}</div>
          <div class="flex gap-2">
            <button
              phx-click="change_page"
              phx-value-direction="prev"
              disabled={@page <= 1}
              class="px-3 py-1 text-sm font-medium rounded-md border border-gray-200 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed dark:bg-gray-900 dark:text-gray-200 dark:border-gray-700 dark:hover:bg-gray-800"
            >
              Previous
            </button>
            <button
              phx-click="change_page"
              phx-value-direction="next"
              disabled={!@has_next_page}
              class="px-3 py-1 text-sm font-medium rounded-md border border-gray-200 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed dark:bg-gray-900 dark:text-gray-200 dark:border-gray-700 dark:hover:bg-gray-800"
            >
              Next
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Sessions table --%>
      <%= if @sessions == [] do %>
        <div class="text-center py-16 text-gray-400">
          <p class="text-4xl mb-3">📦</p>
          <p class="text-lg font-medium">No sessions found.</p>
        </div>
      <% else %>
        <div class="bg-white dark:bg-gray-800 rounded-xl shadow border border-gray-100 dark:border-gray-700 overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 dark:bg-gray-700">
              <tr>
                <th class="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-300">
                  Locker
                </th>
                <th class="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-300">
                  Visitor
                </th>
                <th class="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-300">
                  Assigned At
                </th>
                <th class="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-300">
                  Released At
                </th>
                <th class="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-300">
                  Method
                </th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 dark:divide-gray-700">
              <%= for session <- @sessions do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                  <td class="px-4 py-3 font-mono font-semibold">
                    {session.locker.locker_number}
                  </td>
                  <td class="px-4 py-3">
                    <div class="font-medium">{session.visitor_identifier}</div>
                    <%= if session.visitor_name do %>
                      <div class="text-xs text-gray-400">{session.visitor_name}</div>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                    {format_dt(session.assigned_at)}
                  </td>
                  <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                    <%= if session.released_at do %>
                      {format_dt(session.released_at)}
                    <% else %>
                      <span class="text-red-500 font-medium">Active</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                    {session.release_method || "—"}
                  </td>
                  <td class="px-4 py-3 text-right">
                    <%= if is_nil(session.released_at) do %>
                      <button
                        phx-click="release_session"
                        phx-value-id={session.id}
                        data-confirm="Release this locker?"
                        class="px-3 py-1 text-xs font-medium text-red-600 border border-red-200 rounded hover:bg-red-50 dark:text-red-200 dark:border-red-600 dark:hover:bg-red-600/20"
                      >
                        Release
                      </button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_dt(nil), do: "—"

  defp format_dt(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y %H:%M")
  end

  defp staff_email(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{email: email}} -> email
      _ -> "staff"
    end
  end
end
