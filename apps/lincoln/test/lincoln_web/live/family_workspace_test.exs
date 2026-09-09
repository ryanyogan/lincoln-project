defmodule LincolnWeb.FamilyWorkspaceTest do
  use LincolnWeb.ConnCase
  import Phoenix.LiveViewTest
  import Mox
  alias Lincoln.{Agents, Beliefs, Conversation, FamilyJournal}
  alias Lincoln.Cognition.BeliefRevision

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "home offers three primary destinations and keeps the workshop secondary", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#talk-welcome")
    assert has_element?(view, "#primary-navigation a[aria-current=page]", "Talk")
    assert has_element?(view, "#primary-navigation a[href='/journal']")
    assert has_element?(view, "#primary-navigation a[href='/goals']")
    refute has_element?(view, "#primary-navigation a[href='/substrate']")
    assert has_element?(view, "#workshop-menu:not([open])")
    assert has_element?(view, "#chat-form textarea")
    view |> form("#chat-form", message: "   ") |> render_submit()
    assert has_element?(view, "#talk-welcome")
  end

  test "journal preserves attribution, validates, searches, and exports", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/journal")

    view
    |> form("#journal-form", entry: %{author: "", kind: "story", content: "A memory"})
    |> render_submit()

    assert has_element?(view, "#journal-empty")
    words = "Our favorite walk.\nThe long way home."

    view
    |> form("#journal-form", entry: %{author: "Dad", kind: "story", content: words})
    |> render_submit()

    refute has_element?(view, "#journal-entries article", "A memory")
    assert has_element?(view, "#journal-entries article", "Dad")
    assert has_element?(view, "#journal-entries .entry-words", "The long way home.")
    view |> form("#journal-search", search: "no match") |> render_change()
    refute has_element?(view, "#journal-entries article")
    view |> form("#journal-search", search: "walk") |> render_change()
    assert has_element?(view, "#journal-entries article")
    conn = get(conn, ~p"/journal/export")

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="lincoln-family-journal.json")
           ]

    assert [%{"content" => ^words, "source_context" => %{"author" => "Dad"}}] =
             json_response(conn, 200)["entries"]
  end

  test "a corrected account reaches the next conversation without the superseded claim", %{
    conn: conn
  } do
    {:ok, agent} = Agents.get_or_create_default_agent()
    vector = [1.0 | List.duplicate(0.0, 383)]
    stub(Lincoln.EmbeddingsMock, :embed, fn _, _ -> {:ok, vector} end)

    {:ok, old} =
      Beliefs.create_belief(agent, %{
        statement: "Our walks are on Saturday",
        source_type: "inference",
        confidence: 0.6,
        embedding: Pgvector.new(vector)
      })

    evidence = %{
      statement: "Our walks are now on Sunday",
      source_type: :testimony,
      strength: :strong,
      source_evidence: "Dad's correction"
    }

    decision = BeliefRevision.should_revise?(old, evidence)
    {:ok, corrected} = BeliefRevision.execute_revision(old, evidence, decision)
    {:ok, _} = Beliefs.update_belief(corrected, %{embedding: Pgvector.new(vector)})

    expect(Lincoln.LLMMock, :chat, fn _, opts ->
      prompt = Keyword.fetch!(opts, :system)
      assert prompt =~ "Our walks are now on Sunday"
      refute prompt =~ "Our walks are on Saturday"
      {:ok, "The corrected account says Sunday."}
    end)

    {:ok, view, _} = live(conn, ~p"/")
    view |> form("#chat-form", message: "Hello Lincoln") |> render_submit()
    render_async(view, 5_000)
    assert has_element?(view, "#messages-stream .message-content", "corrected account")
  end

  test "chat reads original family context even without an embedding service", %{conn: conn} do
    {:ok, agent} = Agents.get_or_create_default_agent()

    {:ok, entry} =
      FamilyJournal.record(agent, %{
        "author" => "Dad",
        "kind" => "value",
        "content" => "Take time to listen before giving advice."
      })

    stub(Lincoln.EmbeddingsMock, :embed, fn _, _ -> {:error, :unavailable} end)

    expect(Lincoln.LLMMock, :chat, fn _, opts ->
      prompt = Keyword.fetch!(opts, :system)
      assert prompt =~ entry.id
      assert prompt =~ "Dad"
      assert prompt =~ "Take time to listen"
      {:ok, "Dad wrote about making time to listen."}
    end)

    {:ok, view, _} = live(conn, ~p"/")
    view |> form("#chat-form", message: "Hello Lincoln") |> render_submit()
    render_async(view, 5_000)
    assert has_element?(view, "#messages-stream .message-content", "Dad wrote")
    refute has_element?(view, "#response-pending")
    [conversation] = Conversation.list_conversations(agent.id)
    assert length(Conversation.get_conversation_with_messages(conversation.id).messages) == 2
  end
end
