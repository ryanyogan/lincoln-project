defmodule Lincoln.Adapters.Embeddings do
  @moduledoc """
  Behaviour for embedding adapters.

  Defines the interface for generating text embeddings.
  The actual embedding generation is done by a Python service
  running sentence-transformers.
  """

  @type embedding :: [float()]
  @type response :: {:ok, embedding()} | {:error, term()}
  @type batch_response :: {:ok, [embedding()]} | {:error, term()}

  @doc """
  Generates an embedding for a single text.
  """
  @callback embed(text :: String.t(), opts :: keyword()) :: response()

  @doc """
  Generates embeddings for multiple texts.
  """
  @callback embed_batch(texts :: [String.t()], opts :: keyword()) :: batch_response()

  @doc """
  Computes cosine similarity between two embeddings.
  """
  @callback similarity(embedding1 :: embedding(), embedding2 :: embedding()) :: float()

  @doc """
  Generates a semantic hash from an embedding for quick comparison.
  """
  @callback semantic_hash(embedding :: embedding()) :: String.t()
end

defmodule Lincoln.Adapters.Embeddings.PythonService do
  @moduledoc """
  Embedding adapter that calls the Python ML service.

  The Python service runs sentence-transformers to generate embeddings.
  """
  @behaviour Lincoln.Adapters.Embeddings

  @impl true
  def embed(text, opts \\ []) do
    config = get_config(opts)
    url = "#{config.service_url}/embed"

    case Req.post(url, json: %{text: text}, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"embedding" => embedding}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        {:error, {:service_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def embed_batch(texts, opts \\ []) when is_list(texts) do
    config = get_config(opts)
    url = "#{config.service_url}/embed/batch"

    case Req.post(url, json: %{texts: texts}, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"embeddings" => embeddings}}} ->
        {:ok, embeddings}

      {:ok, %{status: status, body: body}} ->
        {:error, {:service_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def similarity(embedding1, embedding2) do
    # Cosine similarity calculation
    dot_product =
      Enum.zip(embedding1, embedding2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()

    magnitude1 = :math.sqrt(Enum.map(embedding1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(embedding2, &(&1 * &1)) |> Enum.sum())

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  @impl true
  def semantic_hash(embedding) do
    # Create a hash by quantizing the embedding to a binary string
    # This allows quick comparison for near-duplicate detection
    embedding
    |> Enum.map(fn x -> if x >= 0, do: "1", else: "0" end)
    |> Enum.join()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  defp get_config(opts) do
    app_config = Application.get_env(:lincoln, :embeddings, [])

    %{
      service_url:
        Keyword.get(opts, :service_url) ||
          Keyword.get(app_config, :service_url, "http://localhost:8000")
    }
  end
end

defmodule Lincoln.Adapters.Embeddings.Mock do
  @moduledoc """
  Mock embedding adapter for testing.

  Generates deterministic fake embeddings based on text hash.
  """
  @behaviour Lincoln.Adapters.Embeddings

  @dimensions 384

  @impl true
  def embed(text, _opts \\ []) do
    {:ok, generate_fake_embedding(text)}
  end

  @impl true
  def embed_batch(texts, _opts \\ []) do
    embeddings = Enum.map(texts, &generate_fake_embedding/1)
    {:ok, embeddings}
  end

  @impl true
  def similarity(embedding1, embedding2) do
    dot_product =
      Enum.zip(embedding1, embedding2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()

    magnitude1 = :math.sqrt(Enum.map(embedding1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(embedding2, &(&1 * &1)) |> Enum.sum())

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  @impl true
  def semantic_hash(embedding) do
    embedding
    |> Enum.map(fn x -> if x >= 0, do: "1", else: "0" end)
    |> Enum.join()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  defp generate_fake_embedding(text) do
    # Generate a deterministic embedding based on text hash
    hash = :crypto.hash(:sha256, text)

    # Use the hash to seed random-ish but deterministic values
    hash
    |> :binary.bin_to_list()
    |> Stream.cycle()
    |> Enum.take(@dimensions)
    |> Enum.map(fn byte -> (byte - 128) / 128.0 end)
  end
end
