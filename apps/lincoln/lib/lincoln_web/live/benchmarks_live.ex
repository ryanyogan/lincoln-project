defmodule LincolnWeb.BenchmarksLive do
  use LincolnWeb, :live_view

  alias Lincoln.{Agents, Benchmarks}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    runs = Benchmarks.list_runs(agent.id)

    {:ok,
     socket
     |> assign(:page_title, "Benchmarks")
     |> assign(:agent, agent)
     |> assign(:runs, runs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto max-w-3xl p-6">
        <.page_header
          title="Benchmarks"
          subtitle="Quantitative performance tracking · run with mix lincoln.benchmark.run"
          icon="hero-chart-bar"
          icon_color="text-primary"
        />

        <%= if @runs == [] do %>
          <.empty_state
            icon="hero-chart-bar"
            title="No benchmark runs yet"
            description="Run mix lincoln.benchmark.run to evaluate contradiction detection accuracy."
          />
        <% else %>
          <div class="space-y-4">
            <%= for run <- @runs do %>
              <.run_card run={run} />
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp status_badge_type("completed"), do: :success
  defp status_badge_type("running"), do: :info
  defp status_badge_type("failed"), do: :error
  defp status_badge_type(_), do: :default

  defp run_card(assigns) do
    accuracy =
      if assigns.run.total_tasks > 0,
        do: round(assigns.run.correct_tasks / assigns.run.total_tasks * 100),
        else: 0

    assigns = assign(assigns, :accuracy, accuracy)

    ~H"""
    <div class="border-2 border-base-content/10 rounded p-4 shadow-brutal-sm">
      <div class="flex items-start justify-between">
        <div>
          <div class="font-terminal text-sm text-base-content/70">{@run.domain}</div>
          <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40 mt-1">
            {Calendar.strftime(@run.inserted_at, "%Y-%m-%d %H:%M")}
          </div>
        </div>
        <div class="text-right">
          <div class="font-terminal text-2xl text-primary">{@accuracy}%</div>
          <div class="text-[10px] font-terminal uppercase tracking-widest text-base-content/40">
            {@run.correct_tasks}/{@run.total_tasks} correct
          </div>
        </div>
      </div>
      <div class="mt-3 flex items-center gap-3">
        <.badge type={status_badge_type(@run.status)}>
          {@run.status}
        </.badge>
        <%= if @run.notes do %>
          <span class="text-base-content/30 text-xs font-terminal">{@run.notes}</span>
        <% end %>
      </div>
    </div>
    """
  end
end
