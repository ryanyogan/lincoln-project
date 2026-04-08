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
        <div class="mb-8">
          <h1 class="font-terminal text-xl text-primary">BENCHMARKS</h1>
          <p class="text-base-content/30 text-xs mt-1">
            Quantitative performance tracking ·
            run with <code class="font-mono">mix lincoln.benchmark.run</code>
          </p>
        </div>

        <%= if @runs == [] do %>
          <div class="text-center py-20">
            <p class="font-terminal text-base-content/20 text-sm mb-3">NO BENCHMARK RUNS YET</p>
            <p class="text-base-content/20 text-xs max-w-sm mx-auto leading-relaxed">
              Run <code class="font-mono">mix lincoln.benchmark.run</code>
              to evaluate contradiction detection accuracy.
            </p>
          </div>
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

  defp run_card(assigns) do
    accuracy =
      if assigns.run.total_tasks > 0,
        do: round(assigns.run.correct_tasks / assigns.run.total_tasks * 100),
        else: 0

    assigns = assign(assigns, :accuracy, accuracy)

    ~H"""
    <div class="border border-base-content/10 rounded p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="font-terminal text-sm text-base-content/70">{@run.domain}</div>
          <div class="font-terminal text-xs text-base-content/30 mt-1">
            {Calendar.strftime(@run.inserted_at, "%Y-%m-%d %H:%M")}
          </div>
        </div>
        <div class="text-right">
          <div class="font-terminal text-2xl text-primary">{@accuracy}%</div>
          <div class="font-terminal text-xs text-base-content/30">
            {@run.correct_tasks}/{@run.total_tasks} correct
          </div>
        </div>
      </div>
      <div class="mt-3 flex items-center gap-3">
        <span class={[
          "px-2 py-0.5 rounded font-terminal text-xs",
          @run.status == "completed" && "bg-success/20 text-success",
          @run.status == "running" && "bg-info/20 text-info animate-pulse",
          @run.status == "failed" && "bg-error/20 text-error"
        ]}>
          {@run.status}
        </span>
        <%= if @run.notes do %>
          <span class="text-base-content/30 text-xs">{@run.notes}</span>
        <% end %>
      </div>
    </div>
    """
  end
end
