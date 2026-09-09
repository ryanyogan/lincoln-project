defmodule LincolnWeb.JournalLive do
  use LincolnWeb, :live_view
  alias Lincoln.{Agents, FamilyJournal}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    entries = FamilyJournal.list(agent)

    {:ok,
     socket
     |> assign(
       agent: agent,
       page_title: "Family journal",
       search: "",
       offset: length(entries),
       more?: length(entries) == 30
     )
     |> assign(form: to_form(FamilyJournal.changeset(%{"kind" => "story"}), as: :entry))
     |> assign(search_form: to_form(%{"search" => ""}))
     |> stream(:entries, entries)}
  end

  @impl true
  def handle_event("save", %{"entry" => params}, socket) do
    case FamilyJournal.record(socket.assigns.agent, params) do
      {:ok, _entry} ->
        entries = FamilyJournal.list(socket.assigns.agent)

        {:noreply,
         socket
         |> assign(
           form:
             to_form(FamilyJournal.changeset(%{"kind" => "story", "author" => params["author"]}),
               as: :entry
             )
         )
         |> assign(
           search: "",
           search_form: to_form(%{"search" => ""}),
           offset: length(entries),
           more?: length(entries) == 30
         )
         |> stream(:entries, entries, reset: true)
         |> put_flash(:info, "Saved in your words.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :entry))}
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    entries = FamilyJournal.list(socket.assigns.agent, search: search)

    {:noreply,
     socket
     |> assign(
       search: search,
       search_form: to_form(%{"search" => search}),
       offset: length(entries),
       more?: length(entries) == 30
     )
     |> stream(:entries, entries, reset: true)}
  end

  def handle_event("more", _, socket) do
    entries =
      FamilyJournal.list(socket.assigns.agent,
        search: socket.assigns.search,
        offset: socket.assigns.offset
      )

    {:noreply,
     socket
     |> assign(offset: socket.assigns.offset + length(entries), more?: length(entries) == 30)
     |> stream(:entries, entries)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :local_inference_only,
        Application.get_env(:lincoln, :local_inference_only, false)
      )

    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <div class="journal-page">
        <header class="page-intro">
          <span class="eyebrow">The things worth keeping</span>
          <h1>In your own words.</h1>
          <p>
            Stories, values, little details. A place for your family’s voice, preserved as you wrote it.
          </p>
          <.link href={~p"/journal/export"} class="text-link" id="export-journal">
            Download your journal <.icon name="hero-arrow-down-tray" class="size-4" />
          </.link>
        </header>
        <div class="journal-grid">
          <section class="journal-compose" aria-label="Write a journal entry">
            <h2>Leave something here</h2>
            <.form for={@form} id="journal-form" phx-submit="save" class="family-form">
              <.input
                field={@form[:author]}
                label="Whose words are these?"
                placeholder="Your name"
                class="family-input"
                required
                maxlength="100"
              />
              <.input
                field={@form[:kind]}
                type="select"
                label="What would you like to share?"
                options={[
                  {"A story", "story"},
                  {"Something I believe in", "value"},
                  {"A preference", "preference"},
                  {"A correction or update", "correction"}
                ]}
                class="family-input"
              />
              <.input
                field={@form[:content]}
                type="textarea"
                label="Your words"
                placeholder="A moment you remember. Something you want them to know. Why you see the world the way you do."
                rows="8"
                class="family-input"
                required
                maxlength="20000"
              />
              <button type="submit" class="family-button" phx-disable-with="Saving…">
                Keep this
              </button>
            </.form>
            <p class="muted small">
              Lincoln can use recent entries in conversation and will be instructed to name the author. Add a correction as a new entry to preserve the original.
            </p>
            <p :if={!@local_inference_only} class="muted small">
              A cloud model is configured. Relevant journal entries may be included when you talk to Lincoln.
            </p>
          </section>
          <section aria-label="Journal entries">
            <.form for={@search_form} id="journal-search" phx-change="search" phx-submit="search">
              <.input
                field={@search_form[:search]}
                type="search"
                label="Find something in your journal"
                placeholder="Search your words…"
                phx-debounce="250"
                class="family-input"
              />
            </.form>
            <div id="journal-entries" phx-update="stream" class="journal-entries">
              <div id="journal-empty" class="hidden only:block empty-journal">
                <h2>A beginning, whenever you’re ready.</h2>
                <p>No entries to show. Write something here, or try a different search.</p>
              </div>
              <article :for={{id, entry} <- @streams.entries} id={id} class="journal-entry">
                <div class="entry-meta">
                  <span>{entry.source_context["author"]}</span><span>{entry.source_context["kind"]} · {Calendar.strftime(entry.inserted_at, "%b %d, %Y")}</span>
                </div>
                <div class="entry-words">{entry.content}</div>
                <span class="original-label">Original words</span>
              </article>
            </div>
            <button :if={@more?} id="journal-more" phx-click="more" class="family-button secondary">
              Older entries
            </button>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
