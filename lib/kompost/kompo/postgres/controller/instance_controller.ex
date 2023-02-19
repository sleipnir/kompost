defmodule Kompost.Kompo.Postgres.Controller.InstanceController do
  use Bonny.ControllerV2

  require Logger

  alias Kompost.Kompo.Postgre.Instance

  step(Bonny.Pluggable.SkipObservedGenerations)
  step(:handle_event)

  @impl true
  def rbac_rules() do
    [
      to_rbac_rule({"v1", "Secret", ["get", "list"]})
    ]
  end

  @spec handle_event(Bonny.Axn.t(), Keyword.t()) :: Bonny.Axn.t()
  def handle_event(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    with {:cred, {:ok, connection_args}} <- {:cred, get_connection_args(axn.resource, axn.conn)},
         axn <- set_condition(axn, "Credentials", true),
         {:id, id} <-
           {:id, Instance.get_id(axn.resource)},
         {:conn, axn, {:ok, conn}} <- {:conn, axn, Instance.connect(id, connection_args)},
         axn <- set_condition(axn, "Connected", true, "Connection to database was established"),
         {:privileges, :ok} <- {:privileges, Instance.check_privileges(conn)},
         axn <-
           set_condition(axn, "Privileged", true, "The conneted user has the required privileges") do
      success_event(axn)
    else
      {:cred, {:error, error}} ->
        Logger.warn("Error when trying to fetch password.", error: error)

        axn
        |> failure_event(message: Exception.message(error))
        |> set_condition("Credentials", false, Exception.message(error))

      {:conn, axn, {:error, error}} ->
        axn
        |> failure_event(message: Exception.message(error))
        |> set_condition("Connected", false, Exception.message(error))

      {:privileges, {:error, message}} ->
        axn
        |> failure_event(message: message)
        |> set_condition("Privileged", false, message)
    end
  end

  def handle_event(%Bonny.Axn{action: :delete} = axn, _opts) do
    :ok =
      axn.resource
      |> Instance.get_id()
      |> Instance.disconnect()

    success_event(axn)
  end

  @spec get_connection_args(map(), K8s.Conn.t()) ::
          {:ok, [Postgrex.start_option()]} | {:error, K8s.Client.Runner.Base.error_t()}
  defp get_connection_args(%{"spec" => %{"plainPassword" => _} = spec}, _conn) do
    {:ok,
     [
       hostname: spec["hostname"],
       port: spec["port"],
       username: spec["username"],
       password: spec["plainPassword"],
       database: "postgres"
     ]}
  end

  defp get_connection_args(instance, conn) do
    %{
      "metadata" => %{"namespace" => namespace},
      "spec" => %{"passwordSecretRef" => %{"name" => secret_name, "key" => key} = secret_ref}
    } = instance

    with {:ok, secret} <-
           K8s.Client.get("v1", "Secret",
             name: secret_name,
             namespace: secret_ref["namespace"] || namespace
           )
           |> K8s.Client.put_conn(conn)
           |> K8s.Client.run() do
      password = Base.decode64!(secret["data"][key])
      instance = put_in(instance, ~w(spec plainPassword), password)
      get_connection_args(instance, conn)
    end
  end
end
