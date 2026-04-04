defmodule VoileLockerLuggageWeb do
  @moduledoc """
  Shared helpers for VoileLockerLuggage LiveView modules.
  Only depends on phoenix_live_view (no host app dependency).
  """

  @compile {:no_warn_undefined, [VoileWeb.Auth.Authorization, Voile.Repo]}

  def live_view do
    quote do
      use Phoenix.LiveView
      import Phoenix.Component
      import Phoenix.HTML.Form, only: []
    end
  end

  def current_scope_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} -> user
      _ -> nil
    end
  end

  def current_user_node_id(socket) do
    case current_scope_user(socket) do
      %{node_id: node_id} -> node_id
      _ -> nil
    end
  end

  @doc """
  Populates auth-related assigns on the socket from either `current_scope` (when
  the LiveView is mounted directly by the router) or from session data injected by
  `PluginRouterLive` (when the LiveView is rendered via `live_render/3`).

  Sets: `:is_super_admin`, `:is_node_admin`, `:current_user_node_id`
  """
  def mount_auth(socket, session) do
    case socket.assigns[:current_scope] do
      %{user: _} ->
        socket
        |> Phoenix.Component.assign(:is_super_admin, is_super_admin?(socket))
        |> Phoenix.Component.assign(:is_node_admin, is_node_admin?(socket))
        |> Phoenix.Component.assign(:current_user_node_id, current_user_node_id(socket))

      _ ->
        socket
        |> Phoenix.Component.assign(:is_super_admin, Map.get(session, "is_super_admin", false))
        |> Phoenix.Component.assign(:is_node_admin, Map.get(session, "is_node_admin", false))
        |> Phoenix.Component.assign(:current_user_node_id, Map.get(session, "user_node_id"))
    end
  end

  def is_super_admin?(socket) do
    if function_exported?(VoileWeb.Auth.Authorization, :is_super_admin?, 1) do
      VoileWeb.Auth.Authorization.is_super_admin?(socket)
    else
      false
    end
  end

  def is_node_admin?(socket) do
    if function_exported?(VoileWeb.Auth.Authorization, :is_node_admin?, 1) do
      VoileWeb.Auth.Authorization.is_node_admin?(socket)
    else
      false
    end
  end

  def is_staff?(socket) do
    if function_exported?(VoileWeb.Auth.Authorization, :is_staff?, 1) do
      VoileWeb.Auth.Authorization.is_staff?(socket)
    else
      socket
      |> current_scope_user()
      |> has_role?(~w(staff admin super_admin librarian archivist gallery_curator museum_curator))
    end
  end

  def has_role?(%{roles: roles}, role_names) when is_list(roles) do
    roles
    |> Enum.map(& &1.name)
    |> Enum.any?(&(&1 in role_names))
  end

  def has_role?(user, role_names) when is_map(user) do
    user = preload_roles(user)
    has_role?(user, role_names)
  end

  defp preload_roles(user) do
    case Map.get(user, :roles) do
      roles when is_list(roles) and roles != [] -> user
      _ -> Voile.Repo.preload(user, :roles)
    end
  end
end
