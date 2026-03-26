defmodule Lincoln.AgentsTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.Agents
  alias Lincoln.Agents.Agent

  describe "agents" do
    @valid_attrs %{
      name: "Test Agent",
      description: "A test agent",
      personality: %{curiosity: 0.8}
    }
    @update_attrs %{
      name: "Updated Agent",
      description: "Updated description"
    }
    @invalid_attrs %{name: nil}

    def agent_fixture(attrs \\ %{}) do
      {:ok, agent} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Agents.create_agent()

      agent
    end

    test "list_agents/0 returns all agents" do
      agent = agent_fixture()
      [fetched] = Agents.list_agents()
      assert fetched.id == agent.id
      assert fetched.name == agent.name
    end

    test "list_active_agents/0 returns only active agents" do
      active_agent = agent_fixture(%{name: "Active", status: "active"})
      _inactive_agent = agent_fixture(%{name: "Inactive", status: "inactive"})

      active_agents = Agents.list_active_agents()
      assert length(active_agents) == 1
      assert hd(active_agents).id == active_agent.id
    end

    test "get_agent!/1 returns the agent with given id" do
      agent = agent_fixture()
      fetched = Agents.get_agent!(agent.id)
      assert fetched.id == agent.id
      assert fetched.name == agent.name
    end

    test "get_agent_by_name/1 returns the agent with given name" do
      agent = agent_fixture()
      assert Agents.get_agent_by_name(agent.name).id == agent.id
    end

    test "get_agent_by_name/1 returns nil for non-existent name" do
      assert Agents.get_agent_by_name("NonExistent") == nil
    end

    test "create_agent/1 with valid data creates an agent" do
      assert {:ok, %Agent{} = agent} = Agents.create_agent(@valid_attrs)
      assert agent.name == "Test Agent"
      assert agent.description == "A test agent"
      assert agent.personality == %{curiosity: 0.8}
      assert agent.status == "active"
      assert agent.beliefs_count == 0
    end

    test "create_agent/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Agents.create_agent(@invalid_attrs)
    end

    test "create_agent/1 enforces unique names" do
      agent_fixture()
      assert {:error, changeset} = Agents.create_agent(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "update_agent/2 with valid data updates the agent" do
      agent = agent_fixture()
      assert {:ok, %Agent{} = agent} = Agents.update_agent(agent, @update_attrs)
      assert agent.name == "Updated Agent"
      assert agent.description == "Updated description"
    end

    test "update_agent/2 with invalid data returns error changeset" do
      agent = agent_fixture()
      assert {:error, %Ecto.Changeset{}} = Agents.update_agent(agent, @invalid_attrs)
      fetched = Agents.get_agent!(agent.id)
      assert fetched.id == agent.id
      assert fetched.name == agent.name
    end

    test "delete_agent/1 deletes the agent" do
      agent = agent_fixture()
      assert {:ok, %Agent{}} = Agents.delete_agent(agent)
      assert_raise Ecto.NoResultsError, fn -> Agents.get_agent!(agent.id) end
    end

    test "change_agent/1 returns a agent changeset" do
      agent = agent_fixture()
      assert %Ecto.Changeset{} = Agents.change_agent(agent)
    end

    test "touch_agent/1 updates last_active_at" do
      agent = agent_fixture()
      assert agent.last_active_at == nil

      {:ok, touched} = Agents.touch_agent(agent)
      assert touched.last_active_at != nil
    end

    test "increment_counter/3 increments the specified counter" do
      agent = agent_fixture()
      assert agent.beliefs_count == 0

      {:ok, updated} = Agents.increment_counter(agent, :beliefs_count)
      assert updated.beliefs_count == 1

      {:ok, updated} = Agents.increment_counter(updated, :beliefs_count, 5)
      assert updated.beliefs_count == 6
    end

    test "get_or_create_default_agent/0 creates Lincoln if not exists" do
      assert {:ok, %Agent{name: "Lincoln"}} = Agents.get_or_create_default_agent()
    end

    test "get_or_create_default_agent/0 returns existing Lincoln" do
      {:ok, first} = Agents.get_or_create_default_agent()
      {:ok, second} = Agents.get_or_create_default_agent()
      assert first.id == second.id
    end
  end
end
