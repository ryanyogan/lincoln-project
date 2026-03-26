defmodule Lincoln.QuestionsTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Questions}

  describe "questions" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "ask_question/3 creates a new question", %{agent: agent} do
      {:ok, question} = Questions.ask_question(agent, "What is the meaning of life?")

      assert question.question == "What is the meaning of life?"
      assert question.status == "open"
      assert question.times_asked == 1
      assert question.agent_id == agent.id
    end

    test "ask_question/3 with same semantic_hash increments times_asked", %{agent: agent} do
      hash = "abc123"
      {:ok, q1} = Questions.ask_question(agent, "What is life?", semantic_hash: hash)
      assert q1.times_asked == 1

      {:ok, q2} = Questions.ask_question(agent, "What is life again?", semantic_hash: hash)
      assert q2.id == q1.id
      assert q2.times_asked == 2
    end

    test "list_open_questions/2 returns open questions", %{agent: agent} do
      {:ok, open} = Questions.ask_question(agent, "Open question")
      {:ok, answered} = Questions.ask_question(agent, "Answered question")
      Questions.abandon_question(answered)

      questions = Questions.list_open_questions(agent)
      assert length(questions) == 1
      assert hd(questions).id == open.id
    end

    test "list_investigatable_questions/2 returns questions ready for investigation", %{
      agent: agent
    } do
      {:ok, ready} = Questions.ask_question(agent, "Ready to investigate")

      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      {:ok, later} = Questions.ask_question(agent, "Investigate later", [])

      # Manually set investigate_after for the second question
      later
      |> Ecto.Changeset.change(investigate_after: future)
      |> Repo.update!()

      questions = Questions.list_investigatable_questions(agent)
      assert length(questions) == 1
      assert hd(questions).id == ready.id
    end

    test "abandon_question/1 marks question as abandoned", %{agent: agent} do
      {:ok, question} = Questions.ask_question(agent, "A question")
      {:ok, abandoned} = Questions.abandon_question(question)

      assert abandoned.status == "abandoned"
    end
  end

  describe "findings" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      {:ok, question} = Questions.ask_question(agent, "What is 2+2?")
      %{agent: agent, question: question}
    end

    test "create_finding/3 creates a finding and resolves question", %{
      agent: agent,
      question: question
    } do
      {:ok, finding} =
        Questions.create_finding(agent, question, %{
          answer: "The answer is 4",
          source_type: "investigation",
          confidence: 0.95
        })

      assert finding.answer == "The answer is 4"
      assert finding.source_type == "investigation"
      assert_in_delta finding.confidence, 0.95, 0.001
      assert finding.question_id == question.id

      # Question should be resolved
      resolved = Questions.get_question!(question.id)
      assert resolved.status == "answered"
      assert resolved.resolved_by_finding_id == finding.id
    end

    test "create_serendipitous_finding/2 creates finding without question", %{agent: agent} do
      {:ok, finding} =
        Questions.create_serendipitous_finding(agent, %{
          answer: "Unexpected discovery!"
        })

      assert finding.source_type == "serendipity"
      assert finding.question_id == nil
    end

    test "verify_finding/1 marks finding as verified", %{agent: agent, question: question} do
      {:ok, finding} =
        Questions.create_finding(agent, question, %{
          answer: "Answer",
          source_type: "investigation"
        })

      assert finding.verified == false

      {:ok, verified} = Questions.verify_finding(finding)
      assert verified.verified == true
      assert verified.verified_at != nil
    end
  end

  describe "interests" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "create_interest/2 creates an interest", %{agent: agent} do
      {:ok, interest} =
        Questions.create_interest(agent, %{
          topic: "Machine Learning",
          description: "Curious about how ML works",
          origin_type: "emergent",
          intensity: 0.8
        })

      assert interest.topic == "Machine Learning"
      assert interest.origin_type == "emergent"
      assert_in_delta interest.intensity, 0.8, 0.001
    end

    test "list_interests/1 returns active interests", %{agent: agent} do
      {:ok, _} = Questions.create_interest(agent, %{topic: "AI", origin_type: "emergent"})
      {:ok, _} = Questions.create_interest(agent, %{topic: "Physics", origin_type: "assigned"})

      interests = Questions.list_interests(agent)
      assert length(interests) == 2
    end

    test "explore_interest/1 updates exploration tracking", %{agent: agent} do
      {:ok, interest} = Questions.create_interest(agent, %{topic: "AI", origin_type: "emergent"})
      assert interest.exploration_count == 0

      {:ok, explored} = Questions.explore_interest(interest)
      assert explored.exploration_count == 1
      assert explored.last_explored_at != nil
    end
  end

  describe "action log" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "log_action/3 creates an action log entry", %{agent: agent} do
      {:ok, action} =
        Questions.log_action(agent, "investigate", %{
          description: "Investigating question #123",
          triggered_by: "schedule"
        })

      assert action.action_type == "investigate"
      assert action.description == "Investigating question #123"
      assert action.triggered_by == "schedule"
      assert action.outcome == "pending"
    end

    test "complete_action/3 updates the outcome", %{agent: agent} do
      {:ok, action} = Questions.log_action(agent, "reflect", %{triggered_by: "schedule"})

      {:ok, completed} = Questions.complete_action(action, "success", "Generated 3 insights")

      assert completed.outcome == "success"
      assert completed.outcome_details == "Generated 3 insights"
    end

    test "detect_action_loop/3 detects repetitive actions", %{agent: agent} do
      hash = "repeat_hash_123"

      # Not a loop with just one action
      {:ok, _} =
        Questions.log_action(agent, "ask", %{semantic_hash: hash, triggered_by: "curiosity"})

      refute Questions.detect_action_loop(agent, hash)

      # Add more actions with same hash
      {:ok, _} =
        Questions.log_action(agent, "ask", %{semantic_hash: hash, triggered_by: "curiosity"})

      {:ok, _} =
        Questions.log_action(agent, "ask", %{semantic_hash: hash, triggered_by: "curiosity"})

      # Now it should detect a loop (3+ actions with same hash)
      assert Questions.detect_action_loop(agent, hash)
    end

    test "list_recent_actions/3 returns recent actions", %{agent: agent} do
      {:ok, _} = Questions.log_action(agent, "reflect", %{triggered_by: "schedule"})
      {:ok, _} = Questions.log_action(agent, "investigate", %{triggered_by: "curiosity"})

      actions = Questions.list_recent_actions(agent, 24)
      assert length(actions) == 2
    end
  end

  describe "question clusters" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Test Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "create_cluster/2 creates a cluster", %{agent: agent} do
      {:ok, cluster} =
        Questions.create_cluster(agent, %{
          theme: "Philosophy",
          description: "Questions about existence"
        })

      assert cluster.theme == "Philosophy"
      assert cluster.status == "active"
    end

    test "list_clusters/1 returns active clusters", %{agent: agent} do
      {:ok, _} = Questions.create_cluster(agent, %{theme: "Science"})
      {:ok, _} = Questions.create_cluster(agent, %{theme: "Art"})

      clusters = Questions.list_clusters(agent)
      assert length(clusters) == 2
    end

    test "assign_to_cluster/2 assigns question to cluster", %{agent: agent} do
      {:ok, cluster} = Questions.create_cluster(agent, %{theme: "Science"})
      {:ok, question} = Questions.ask_question(agent, "Why is the sky blue?")

      {:ok, assigned} = Questions.assign_to_cluster(question, cluster)
      assert assigned.cluster_id == cluster.id

      # Cluster count should be updated
      updated_cluster =
        Lincoln.Questions.QuestionCluster
        |> Repo.get!(cluster.id)

      assert updated_cluster.question_count == 1
    end
  end
end
