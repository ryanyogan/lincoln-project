defmodule LincolnWeb.ActionsLive do
  @moduledoc """
  Actions — Lincoln's pending and historical effector calls.

  Phase 7 surface: list pending_approval (tier-2) actions and approve them.
  Approving moves an action from `"pending_approval"` to `"proposed"`, where
  the substrate's `:action` impulse will pick it up and execute through MCP.
  """

  use LincolnWeb, :live_view

  alias Lincoln.{Actions, Agents}
  alias Lincoln.Actions.Action

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, "agent:#{agent.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Actions")
     |> assign(:agent, agent)
     |> assign(:filter, "pending_approval")
     |> stream(:actions, list_for(agent, "pending_approval"))}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    %{agent: agent} = socket.assigns

    {:noreply,
     socket
     |> assign(:filter, status)
     |> stream(:actions, list_for(agent, status), reset: true)}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    action = Actions.get_action!(id)

    case Actions.approve(action) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved #{action.tool_name} — substrate will execute soon.")
         |> stream_delete(:actions, updated)
         |> then(fn s ->
           if s.assigns.filter == "proposed",
             do: stream_insert(s, :actions, updated, at: 0),
             else: s
         end)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not approve action.")}
    end
  end

  @impl true
  def handle_info({:action_logged, action}, socket) do
    if matches_filter?(socket.assigns.filter, action.status) do
      {:noreply, stream_insert(socket, :actions, action, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:action_completed, action}, socket) do
    if matches_filter?(socket.assigns.filter, action.status) do
      {:noreply, stream_insert(socket, :actions, action)}
    else
      {:noreply, stream_delete(socket, :actions, action)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp matches_filter?("all", _status), do: true
  defp matches_filter?(filter, status), do: filter == status

  defp list_for(agent, "all"), do: Actions.list_actions(agent, limit: 100)

  defp list_for(agent, status), do: Actions.list_actions(agent, status: status, limit: 100)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6 max-w-4xl mx-auto">
        <header class="border-b-4 border-base-300 pb-4">
          <h1 class="text-3xl font-terminal uppercase tracking-tight">Actions</h1>
          <p class="text-sm opacity-70 mt-1">
            Tier 0/1 execute autonomously. Tier 2 waits for your approval here.
          </p>
        </header>

        <nav class="flex gap-2 text-xs uppercase font-terminal flex-wrap">
          <button
            :for={f <- ~w(pending_approval proposed executed failed all)}
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

        <ul id="actions-stream" phx-update="stream" class="space-y-3">
          <li id="actions-empty" class="hidden only:block opacity-60 text-sm">
            No actions match this filter.
          </li>
          <li
            :for={{dom_id, action} <- @streams.actions}
            id={dom_id}
            class="border-2 border-base-300 p-4 space-y-2"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex-1">
                <h3 class="font-medium">
                  {action.tool_name}
                  <span class="opacity-60">@ {action.tool_server}</span>
                </h3>
                <div class="text-xs opacity-70 mt-1 flex flex-wrap gap-3">
                  <span>tier {action.risk_tier}</span>
                  <span>{action.reversibility}</span>
                  <span>status {action.status}</span>
                  <span>predicted {confidence_pct(action.prediction_confidence)}</span>
                </div>
                <p :if={action.predicted_outcome} class="text-sm mt-1 italic">
                  → {action.predicted_outcome}
                </p>
                <p :if={action.error} class="text-sm mt-1 text-error">{action.error}</p>
              </div>
              <div class="flex gap-1">
                <button
                  :if={action.status == "pending_approval"}
                  phx-click="approve"
                  phx-value-id={action.id}
                  class="text-xs uppercase border-2 border-primary px-2 py-1 hover:bg-primary hover:text-primary-content"
                >
                  approve
                </button>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp confidence_pct(%Action{} = action), do: confidence_pct(action.prediction_confidence)
  defp confidence_pct(nil), do: "—"
  defp confidence_pct(c), do: "#{round(c * 100)}%"
end
