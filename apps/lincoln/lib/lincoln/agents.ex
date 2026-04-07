defmodule Lincoln.Agents do
  @moduledoc """
  The Agents context.

  Manages agent lifecycle and provides the entry point for agent-related operations.
  """
  import Ecto.Query
  alias Lincoln.Agents.Agent
  alias Lincoln.Repo

  @doc """
  Returns the list of agents.
  """
  def list_agents do
    Repo.all(Agent)
  end

  @doc """
  Returns the list of active agents.
  """
  def list_active_agents do
    Agent
    |> where([a], a.status == "active")
    |> Repo.all()
  end

  @doc """
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.
  """
  def get_agent!(id), do: Repo.get!(Agent, id)

  @doc """
  Gets a single agent. Returns nil if the Agent does not exist.
  """
  def get_agent(id), do: Repo.get(Agent, id)

  @doc """
  Gets a single agent by name.

  Returns nil if the Agent does not exist.
  """
  def get_agent_by_name(name) do
    Repo.get_by(Agent, name: name)
  end

  @doc """
  Creates an agent.
  """
  def create_agent(attrs \\ %{}) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an agent.
  """
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an agent.
  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  @doc """
  Touches the agent's last_active_at timestamp.
  """
  def touch_agent(%Agent{} = agent) do
    agent
    |> Agent.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Increments a counter on the agent.
  """
  def increment_counter(%Agent{} = agent, counter, amount \\ 1) do
    agent
    |> Agent.increment_counter_changeset(counter, amount)
    |> Repo.update()
  end

  @doc """
  Gets or creates a default agent.
  Useful for single-agent scenarios.
  """
  def get_or_create_default_agent do
    case get_agent_by_name("Lincoln") do
      nil ->
        create_agent(%{
          name: "Lincoln",
          description: "The default learning agent",
          personality: %{
            curiosity: 0.8,
            skepticism: 0.6,
            openness: 0.7
          }
        })

      agent ->
        {:ok, agent}
    end
  end
end
