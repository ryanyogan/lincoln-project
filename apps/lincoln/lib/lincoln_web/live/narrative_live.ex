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
        <.page_header
          title="Lincoln's Autobiography"
          subtitle="Self-generated reflections · every 50 substrate ticks (~1 min)"
          icon="hero-book-open"
          icon_color="text-primary"
        >
          <:actions>
            <%= if @reflection_count > 0 do %>
              <.badge type={:default}>
                {@reflection_count} {if @reflection_count == 1, do: "entry", else: "entries"}
              </.badge>
            <% end %>
          </:actions>
        </.page_header>

        <%!-- Reflections feed --%>
        <%= if @reflections == [] do %>
          <.empty_state
            icon="hero-book-open"
            title="No entries yet"
            description="Lincoln writes after every 50 substrate ticks. Start the substrate and the first entry will appear within ~1 minute."
          />
          <div class="text-center mt-6">
            <.link
              navigate={~p"/substrate"}
              class="font-terminal text-xs text-primary/50 hover:text-primary transition-colors"
            >
              {if @substrate_running, do: "→ View substrate", else: "→ Start substrate"}
            </.link>
          </div>
        <% else %>
          <div class="space-y-8">
            <%= for reflection <- @reflections do %>
              <article class="border-l-2 border-2 border-primary/20 pl-5 p-4 shadow-brutal-sm hover:border-primary/40 transition-colors">
                <%!-- Entry metadata --%>
                <div class="flex items-center gap-3 mb-3">
                  <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                    {Calendar.strftime(reflection.inserted_at, "%Y-%m-%d %H:%M")}
                  </span>
                  <span class="text-base-content/20">·</span>
                  <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                    tick {reflection.tick_number}
                  </span>
                  <%= if reflection.thought_count > 0 do %>
                    <span class="text-base-content/20">·</span>
                    <span class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
                      {reflection.thought_count} thoughts completed
                    </span>
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
                      <.badge type={:default}>{topic}</.badge>
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
