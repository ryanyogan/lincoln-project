defmodule Lincoln.Substrate.LocalInferenceTest do
  use ExUnit.Case
  import Mox
  alias Lincoln.Substrate.InferenceTier

  setup :verify_on_exit!

  setup do
    previous_local = Application.get_env(:lincoln, :local_inference_only)
    previous_adapter = Application.get_env(:lincoln, :ollama_adapter)
    Application.put_env(:lincoln, :local_inference_only, true)
    Application.put_env(:lincoln, :ollama_adapter, Lincoln.LLMMock)

    on_exit(fn ->
      restore(:local_inference_only, previous_local)
      restore(:ollama_adapter, previous_adapter)
    end)

    :ok
  end

  test "an unavailable local model returns an error without a frontier fallback" do
    expect(Lincoln.LLMMock, :chat, fn _, _ -> {:error, :ollama_unavailable} end)
    assert {:error, :ollama_unavailable} = InferenceTier.execute_at_tier(:ollama, [], [])
  end

  defp restore(key, nil), do: Application.delete_env(:lincoln, key)
  defp restore(key, value), do: Application.put_env(:lincoln, key, value)
end
