defmodule VoileLockerLuggage.CheckInPanel do
  @moduledoc """
  LiveComponent rendered inside the visitor check-in success modal when the
  Locker & Luggage plugin is active and lockers are available at the selected node.

  This component owns all locker-offer UI and event handling so that the core
  check_in LiveView contains zero plugin-specific code.
  """

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:locker_offered, true)
     |> assign(:locker_assigned_number, nil)
     |> assign(:locker_error, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:node_id, assigns.node_id)
     |> assign(:visitor_log_id, assigns.visitor_log_id)
     |> assign(:visitor_name, assigns.visitor_name)
     |> assign(:visitor_identifier, assigns.visitor_identifier)
     |> assign(:available_count, assigns.available_count)}
  end

  @impl true
  def handle_event("request_locker", _params, socket) do
    %{node_id: node_id, visitor_identifier: visitor_identifier, visitor_name: visitor_name, visitor_log_id: log_id} = socket.assigns

    result =
      try do
        VoileLockerLuggage.Lockers.assign_locker(
          node_id,
          visitor_identifier,
          visitor_name,
          visitor_log_id: log_id
        )
      rescue
        _ -> {:error, :unavailable}
      end

    case result do
      {:ok, session} ->
        locker_number =
          case session.locker do
            %{} = locker -> locker.locker_number
            _ -> session.locker_id
          end

        {:noreply,
         socket
         |> assign(:locker_assigned_number, locker_number)
         |> assign(:locker_offered, false)
         |> assign(:locker_error, nil)}

      {:error, :no_available_lockers} ->
        {:noreply, assign(socket, :locker_error, "No lockers available at this time.")}

      {:error, _} ->
        {:noreply, assign(socket, :locker_error, "Could not assign locker. Please ask staff.")}
    end
  end

  @impl true
  def handle_event("decline_locker", _params, socket) do
    {:noreply, assign(socket, :locker_offered, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"locker-panel-#{@visitor_log_id}"}>
      <%= if @locker_assigned_number do %>
        <div class="mt-4 p-4 bg-green-50 dark:bg-green-900/20 rounded-xl border border-green-200 dark:border-green-700">
          <div class="flex items-center gap-3">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="w-6 h-6 text-green-600"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M20.25 7.5l-.625 10.632a2.25 2.25 0 01-2.247 2.118H6.622a2.25 2.25 0 01-2.247-2.118L3.75 7.5M10 11.25h4M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125z"
              />
            </svg>
            <div class="text-left">
              <p class="font-semibold text-green-800 dark:text-green-200">
                Locker Assigned!
              </p>
              <p class="text-2xl font-bold text-green-700 dark:text-green-300">
                #{@locker_assigned_number}
              </p>
              <p class="text-xs text-green-600 dark:text-green-400 mt-0.5">
                Please remember your locker number and return the key when you leave.
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @locker_offered do %>
        <div class="mt-4 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-xl border border-blue-200 dark:border-blue-700">
          <div class="flex items-center gap-2 mb-3">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="w-5 h-5 text-blue-600"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M20.25 7.5l-.625 10.632a2.25 2.25 0 01-2.247 2.118H6.622a2.25 2.25 0 01-2.247-2.118L3.75 7.5M10 11.25h4M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125z"
              />
            </svg>
            <p class="font-semibold text-blue-800 dark:text-blue-200 text-sm">
              Would you like a locker?
            </p>
          </div>
          <p class="text-xs text-blue-600 dark:text-blue-400 mb-3">
            {if @available_count == 1,
              do: "1 locker is available",
              else: "#{@available_count} lockers are available"}
          </p>
          <%= if @locker_error do %>
            <p class="text-xs text-red-600 mb-2">{@locker_error}</p>
          <% end %>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="request_locker"
              phx-target={@myself}
              class="flex-1 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              Yes, assign me one
            </button>
            <button
              type="button"
              phx-click="decline_locker"
              phx-target={@myself}
              class="flex-1 py-2 border border-gray-300 text-gray-700 dark:text-gray-300 dark:border-gray-600 text-sm font-medium rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
            >
              No thanks
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
