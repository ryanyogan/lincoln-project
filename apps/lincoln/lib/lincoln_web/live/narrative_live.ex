defmodule LincolnWeb.NarrativeLive do
  @moduledoc """
  Lincoln's autobiography — self-generated narrative reflections.

  Every 200 substrate ticks, Lincoln spawns a narrative Thought that
  uses Claude to write a short autobiographical passage. Over time
  these accumulate into Lincoln's autobiography.

  In the divergence demo, two Lincolns with different attention parameters
  write different autobiographies from the same starting conditions.
  """

  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Narratives}
  alias Lincoln.PubSubBroadcaster

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    reflections = Narratives.list_reflections(agent.id, limit: 50)
    reflection_count = Narratives.count_reflections(agent.id)

    substrate_running =
      case Lincoln.Substrate.get_agent_state(agent.id) do
        {:ok, _} -> true
        _ -> false
      end

    # Subscribe to substrate topic to detect new narratives
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.substrate_topic(agent.id))
    end

    {:ok,
     socket
     |> assign(:page_title, "Lincoln's Autobiography")
     |> assign(:agent, agent)
     |> assign(:reflections, reflections)
     |> assign(:reflection_count, reflection_count)
     |> assign(:substrate_running, substrate_running)}
  end

  # Refresh data when substrate ticks (narrative may have been created)
  @impl true
  def handle_info({:tick, _count, _focus, _detail}, socket) do
    reflections = Narratives.list_reflections(socket.assigns.agent.id, limit: 50)
    reflection_count = Narratives.count_reflections(socket.assigns.agent.id)

    {:noreply,
     socket
     |> assign(:reflections, reflections)
     |> assign(:reflection_count, reflection_count)
     |> assign(:substrate_running, true)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto max-w-2xl p-6">
        <%!-- Header --%>
        <div class="mb-8">
          <h1 class="font-terminal text-xl text-primary">LINCOLN'S AUTOBIOGRAPHY</h1>
          <p class="text-base-content/30 text-xs mt-1">
            Self-generated reflections · every 50 substrate ticks (~1 min)
          </p>
          <%= if @reflection_count > 0 do %>
            <div class="font-terminal text-xs text-base-content/40 mt-2">
              {@reflection_count} {if @reflection_count == 1, do: "entry", else: "entries"}
            </div>
          <% end %>
        </div>

        <%!-- Reflections feed --%>
        <%= if @reflections == [] do %>
          <div class="text-center py-20">
            <div class="font-terminal text-base-content/20 text-sm mb-3">NO ENTRIES YET</div>
            <p class="text-base-content/20 text-xs max-w-sm mx-auto leading-relaxed">
              Lincoln writes after every 50 substrate ticks. Start the substrate and
              the first entry will appear within ~1 minute.
            </p>
            <div class="mt-6">
              <.link
                navigate={~p"/substrate"}
                class="font-terminal text-xs text-primary/50 hover:text-primary transition-colors"
              >
                {if @substrate_running, do: "→ View substrate", else: "→ Start substrate"}
              </.link>
            </div>
          </div>
        <% else %>
          <div class="space-y-8">
            <%= for reflection <- @reflections do %>
              <article class="border-l-2 border-primary/20 pl-5 hover:border-primary/40 transition-colors">
                <%!-- Entry metadata --%>
                <div class="flex items-center gap-3 mb-3 font-terminal text-xs text-base-content/30">
                  <time>{Calendar.strftime(reflection.inserted_at, "%Y-%m-%d %H:%M")}</time>
                  <span>·</span>
                  <span>tick {reflection.tick_number}</span>
                  <%= if reflection.thought_count > 0 do %>
                    <span>·</span>
                    <span>{reflection.thought_count} thoughts completed</span>
                  <% end %>
                </div>
                <%!-- The reflection itself — Lincoln's own words --%>
                <p class="text-base-content/75 leading-relaxed text-sm">
                  {reflection.content}
                </p>
                <%!-- Topics if any --%>
                <%= if reflection.dominant_topics != [] do %>
                  <div class="mt-3 flex flex-wrap gap-1">
                    <%= for topic <- Enum.take(reflection.dominant_topics, 5) do %>
                      <span class="text-base-content/25 font-terminal text-xs px-1.5 py-0.5 border border-base-content/10 rounded">
                        {topic}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </article>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
