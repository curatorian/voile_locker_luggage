defmodule VoileLockerLuggage.Migrator do
  @moduledoc "Runs Ecto migrations for the VoileLockerLuggage plugin."

  require Logger

  @otp_app :voile_locker_luggage

  @doc "Run all pending migrations for this plugin."
  def run do
    migrations_path = migrations_path()
    repo = Voile.Repo

    unless File.dir?(migrations_path) do
      Logger.info("[LockerMigrator] No migrations dir for #{@otp_app}, skipping")
      :ok
    else
      case Ecto.Migrator.run(repo, migrations_path, :up, all: true) do
        versions when is_list(versions) -> {:ok, versions}
        _ -> :ok
      end
    end
  rescue
    e -> {:error, "Migration failed for #{@otp_app}: #{Exception.message(e)}"}
  end

  @doc "Roll back all migrations for this plugin."
  def rollback do
    migrations_path = migrations_path()
    repo = Voile.Repo

    case Ecto.Migrator.run(repo, migrations_path, :down, all: true) do
      versions when is_list(versions) -> {:ok, versions}
      _ -> :ok
    end
  rescue
    e -> {:error, "Rollback failed for #{@otp_app}: #{Exception.message(e)}"}
  end

  defp migrations_path do
    case :code.priv_dir(@otp_app) do
      {:error, :bad_name} ->
        raise "Could not find priv dir for :#{@otp_app}"

      path ->
        Path.join(to_string(path), "migrations")
    end
  end
end
