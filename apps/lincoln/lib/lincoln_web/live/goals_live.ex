defmodule LincolnWeb.GoalsLive do
  @moduledoc """
  Goals — Lincoln's explicit pursuit list.

  Read-only Phase 4 surface: list active goals, create goals, mark
  achieved/abandoned. No actions are taken on Lincoln's behalf yet.
  """

  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Goals}
  alias Lincoln.Goals.{Goal, SelfProposer}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}:goals")
    end

    {:ok,
     socket
     |> assign(:page_title, "Commitments")
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

  def handle_event("approve", %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    case SelfProposer.approve(goal) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved self-proposed goal.")
         |> stream_delete(:goals, updated)
         |> then(fn s ->
           if s.assigns.filter in ["all", "active"],
             do: stream_insert(s, :goals, updated, at: 0),
             else: s
         end)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not approve goal.")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    goal = Goals.get_goal!(id)

    case SelfProposer.reject(goal) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rejected self-proposed goal.")
         |> stream_delete(:goals, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reject goal.")}
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
    <Layouts.app flash={@flash} current_path={@current_path}>
      <section class="commitments-page">
        <header class="page-intro">
          <span class="eyebrow">Make room for what matters</span>
          <h1>Things to follow through on.</h1>
          <p>
            Keep a shared intention here. Track what’s open, what needs your input, and what’s done.
          </p>
        </header>
        <.form
          for={@form}
          id="goal-form"
          phx-change="validate"
          phx-submit="save"
          class="family-form commitment-form"
        >
          <.input
            field={@form[:statement]}
            label="A new commitment"
            placeholder="Something you want to follow through on…"
            class="family-input"
            required
          />
          <div class="commitment-options">
            <.input
              field={@form[:priority]}
              type="select"
              label="How important?"
              options={[{"Everyday", 5}, {"Important", 7}, {"Highest priority", 10}]}
              class="family-input"
            />
            <.input
              field={@form[:deadline]}
              type="datetime-local"
              label="By when? (optional)"
              class="family-input"
            />
            <button type="submit" class="family-button" phx-disable-with="Adding…">
              Add commitment
            </button>
          </div>
          <p class="muted small">A place to keep track. This does not send scheduled alerts.</p>
        </.form>
        <nav class="commitment-filters" aria-label="Filter commitments">
          <button
            :for={
              {label, status} <- [
                {"Open", "active"},
                {"Needs input", "pending_user_approval"},
                {"Blocked", "blocked"},
                {"Done", "achieved"},
                {"All", "all"}
              ]
            }
            phx-click="filter"
            phx-value-status={status}
            aria-pressed={@filter == status}
          >
            {label}
          </button>
        </nav>
        <ul id="goals-stream" phx-update="stream">
          <li id="goals-empty" class="hidden only:block empty-journal">
            Nothing here yet. Start with one thing that matters.
          </li>
          <li :for={{dom_id, goal} <- @streams.goals} id={dom_id} class="commitment-item">
            <div>
              <h2>{goal.statement}</h2>
              <p class="commitment-meta">
                {status_label(goal.status)}
                <span :if={goal.deadline}> · Due   {format_dt(goal.deadline)}</span>
              </p>
              <details class="response-context">
                <summary>Details</summary>
                <p>
                  priority {goal.priority}/10 · {goal.origin} · Lincoln’s progress estimate: {round(
                    goal.progress_estimate * 100
                  )}%
                </p>
              </details>
            </div>
            <div class="commitment-actions">
              <button
                :if={goal.status == "pending_user_approval"}
                phx-click="approve"
                phx-value-id={goal.id}
                class="family-button"
              >
                Accept
              </button>
              <button
                :if={goal.status == "pending_user_approval"}
                phx-click="reject"
                phx-value-id={goal.id}
                class="family-button secondary"
              >
                Decline
              </button>
              <button
                :if={goal.status in ~w(active blocked)}
                phx-click="status:achieved"
                phx-value-id={goal.id}
                class="family-button secondary"
              >
                Mark done
              </button>
              <button
                :if={goal.status in ~w(active blocked)}
                phx-click="status:abandoned"
                phx-value-id={goal.id}
                class="family-button secondary"
              >
                Let go
              </button>
            </div>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  defp status_label("active"), do: "Open"
  defp status_label("pending_user_approval"), do: "Waiting for your input"
  defp status_label("achieved"), do: "Done"
  defp status_label("abandoned"), do: "Let go"
  defp status_label(status), do: String.capitalize(status)
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
