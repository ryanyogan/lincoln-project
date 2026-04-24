ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lincoln.Repo, :manual)

# Define Mox mocks for adapters
Mox.defmock(Lincoln.LLMMock, for: Lincoln.Adapters.LLM)
Mox.defmock(Lincoln.EmbeddingsMock, for: Lincoln.Adapters.Embeddings)
Mox.defmock(Lincoln.SearchClientMock, for: Lincoln.MCP.SearchClient)
