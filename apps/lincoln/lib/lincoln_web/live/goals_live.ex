defmodule LincolnWeb.GoalsLive do
  @moduledoc """
  Goals — Lincoln's explicit pursuit list.

  Read-only Phase 4 surface: list active goals, create goals, mark
  achieved/abandoned. No actions are taken on Lincoln's behalf yet.
  """

  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Goals}
  alias Lincoln.Goals.Goal

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:goals")
    end

    {:ok,
     socket
     |> assign(:page_title, "Goals")
     |> assign(:agent, agent)
     |> assign(:filter, "active")
     |> assign(:form, to_form(Goal.changeset(%Goal{}, %{})))
     |> stream(:goals, Goals.list_goals(agent, status: "active"))}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    %{agent: agent} = socket.assigns

    statuses = if status == "all", do: nil, else: status

    {:noreply,
     socket
     |> assign(:filter, status)
     |> stream(:goals, Goals.list_goals(agent, status: statuses), reset: true)}
  end

  def handle_event("validate", %{"goal" => params}, socket) do
    changeset =
      %Goal{}
      |> Goal.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"goal" => params}, socket) do
    %{agent: agent} = socket.assigns

    case Goals.create_goal(agent, normalize_params(params)) do
      {:ok, goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Goal '#{String.slice(goal.statement, 0, 60)}' added.")
         |> assign(:form, to_form(Goal.changeset(%Goal{}, %{})))
         |> stream_insert(:goals, goal, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("status:" <> next_status, %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    case Goals.update_status(goal, next_status) do
      {:ok, updated} ->
        if socket.assigns.filter in ["all", next_status] do
          {:noreply, stream_insert(socket, :goals, updated)}
        else
          {:noreply, stream_delete(socket, :goals, updated)}
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update goal.")}
    end
  end

  @impl true
  def handle_info({:goal_created, goal}, socket) do
    if socket.assigns.filter in ["all", goal.status] do
      {:noreply, stream_insert(socket, :goals, goal, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:goal_updated, goal}, socket) do
    if socket.assigns.filter in ["all", goal.status] do
      {:noreply, stream_insert(socket, :goals, goal)}
    else
      {:noreply, stream_delete(socket, :goals, goal)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp normalize_params(%{"deadline" => ""} = p), do: Map.delete(p, "deadline")
  defp normalize_params(p), do: p

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6 max-w-4xl mx-auto">
        <header class="border-b-4 border-base-300 pb-4">
          <h1 class="text-3xl font-terminal uppercase tracking-tight">Goals</h1>
          <p class="text-sm opacity-70 mt-1">
            Explicit pursuits — Lincoln reasons about progress on each one.
          </p>
        </header>

        <section class="border-2 border-base-300 p-4">
          <h2 class="text-lg font-terminal uppercase mb-3">New goal</h2>
          <.form
            for={@form}
            id="goal-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-3"
          >
            <input
              type="text"
              name="goal[statement]"
              value={@form[:statement].value}
              placeholder="e.g. Submit the school forms by Friday"
              class="input input-bordered w-full"
              autocomplete="off"
            />
            <div class="flex flex-wrap gap-3 items-end">
              <label class="flex flex-col text-xs uppercase font-terminal">
                Priority
                <input
                  type="number"
                  name="goal[priority]"
                  value={@form[:priority].value || 5}
                  min="1"
                  max="10"
                  class="input input-bordered w-24"
                />
              </label>
              <label class="flex flex-col text-xs uppercase font-terminal">
                Deadline (optional)
                <input
                  type="datetime-local"
                  name="goal[deadline]"
                  value={@form[:deadline].value}
                  class="input input-bordered"
                />
              </label>
              <button type="submit" class="btn btn-primary font-terminal uppercase">
                Add goal
              </button>
            </div>
            <p
              :for={msg <- Enum.map(@form[:statement].errors, &translate_error/1)}
              class="text-sm text-error"
            >
              {msg}
            </p>
          </.form>
        </section>

        <nav class="flex gap-2 text-xs uppercase font-terminal">
          <button
            :for={f <- ~w(active blocked achieved abandoned all)}
            phx-click="filter"
            phx-value-status={f}
            class={[
              "border-2 px-3 py-1",
              if(@filter == f,
                do: "border-primary bg-primary text-primary-content",
                else: "border-base-300 hover:border-primary"
              )
            ]}
          >
            {f}
          </button>
        </nav>

        <ul id="goals-stream" phx-update="stream" class="space-y-3">
          <li id="goals-empty" class="hidden only:block opacity-60 text-sm">
            No goals match this filter yet.
          </li>
          <li
            :for={{dom_id, goal} <- @streams.goals}
            id={dom_id}
            class="border-2 border-base-300 p-4 space-y-2"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex-1">
                <h3 class="font-medium">{goal.statement}</h3>
                <div class="text-xs opacity-70 mt-1 flex flex-wrap gap-3">
                  <span>priority {goal.priority}/10</span>
                  <span>status {goal.status}</span>
                  <span>origin {goal.origin}</span>
                  <span>progress {Float.round(goal.progress_estimate * 100, 0)}%</span>
                  <span :if={goal.deadline}>due {format_dt(goal.deadline)}</span>
                </div>
              </div>
              <div class="flex gap-1">
                <button
                  :if={goal.status in ~w(active blocked)}
                  phx-click="status:achieved"
                  phx-value-id={goal.id}
                  class="text-xs uppercase border-2 border-success px-2 py-1 hover:bg-success hover:text-success-content"
                >
                  achieved
                </button>
                <button
                  :if={goal.status in ~w(active blocked)}
                  phx-click="status:abandoned"
                  phx-value-id={goal.id}
                  class="text-xs uppercase border-2 border-error px-2 py-1 hover:bg-error hover:text-error-content"
                >
                  abandon
                </button>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp format_dt(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_string()
end
