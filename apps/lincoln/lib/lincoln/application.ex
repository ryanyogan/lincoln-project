defmodule Lincoln.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LincolnWeb.Telemetry,
      Lincoln.Repo,
      {DNSCluster, query: Application.get_env(:lincoln, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Lincoln.PubSub},
      {Registry, keys: :unique, name: Lincoln.AgentRegistry},
      {DynamicSupervisor, name: Lincoln.AgentSupervisor, strategy: :one_for_one},
      # Oban for background job processing
      {Oban, Application.fetch_env!(:lincoln, Oban)},
      # Events cache for fast pattern analysis
      Lincoln.Events.Cache,
      # Start to serve requests, typically the last entry
      LincolnWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lincoln.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LincolnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
