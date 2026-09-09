defmodule Lincoln.Substrate.ReflectionFeedback do
  @moduledoc "Reflection proposes questions; it cannot certify its own evidence."
  alias Lincoln.{Cognition, Questions}

  def apply(agent, belief, result) do
    case Cognition.evaluate_reflection(result) do
      :reinforce ->
        :unverified

      :challenge ->
        Questions.ask_question(
          agent,
          "What independent evidence tests this claim: #{belief.statement}?",
          semantic_hash: "reflection:challenge:#{belief.id}",
          priority: 6,
          context:
            "Reflection raised a concern about belief #{belief.id}. Reflection alone does not change its confidence."
        )

      {:extend, insight} ->
        Questions.ask_question(
          agent,
          "What evidence supports or refutes this possibility: #{insight}?",
          semantic_hash:
            "reflection:extension:#{belief.id}:#{:crypto.hash(:sha256, insight) |> Base.encode16()}",
          priority: 5,
          context: "Unverified inference from reflection on belief #{belief.id}."
        )
    end
  end
end
