import Config
import Dotenvy

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# Load .env file in dev/test environments, fall back to just System.get_env() in prod
# The .env file should be at the project root (../../../.env relative to apps/lincoln/config)
# System.get_env() is included last so real env vars take precedence over .env file
source!(
  if config_env() in [:dev, :test] do
    [
      Path.expand("../../../.env", __DIR__),
      System.get_env()
    ]
  else
    [System.get_env()]
  end
)

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/lincoln start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if env!("PHX_SERVER", :boolean, false) do
  config :lincoln, LincolnWeb.Endpoint, server: true
end

config :lincoln, LincolnWeb.Endpoint, http: [port: env!("PORT", :integer, 4000)]

# LLM Configuration - load API keys from environment
# In prod, at least one provider key is required; in dev/test they're optional (can be mocked)
anthropic_api_key = env!("ANTHROPIC_API_KEY", :string, nil)
openai_api_key = env!("OPENAI_API_KEY", :string, nil)

if config_env() == :prod do
  unless anthropic_api_key || openai_api_key do
    raise """
    At least one LLM API key is required.
    Set ANTHROPIC_API_KEY or OPENAI_API_KEY (or both).
    """
  end
end

if anthropic_api_key do
  config :lincoln, :llm, api_key: anthropic_api_key
end

if openai_api_key do
  config :lincoln, :openai, api_key: openai_api_key
end

# Select the frontier LLM adapter based on LLM_PROVIDER env var
# Defaults to :anthropic. Set LLM_PROVIDER=openai to use OpenAI.
# In :test we leave the adapter set by test.exs (Lincoln.LLMMock) — runtime.exs
# runs after test.exs and would otherwise clobber the mock with a real adapter
# whenever a developer's .env includes LLM_PROVIDER.
unless config_env() == :test do
  llm_provider = env!("LLM_PROVIDER", :string, "anthropic")

  case llm_provider do
    "openai" ->
      config :lincoln, :llm_adapter, Lincoln.Adapters.LLM.OpenAI

    _ ->
      config :lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic
  end
end

# Tavily web search — pick up the API key from env. When present we switch
# the search adapter to the Tavily impl so investigation grounds against
# the live web; otherwise the NoOp adapter keeps investigation LLM-only.
tavily_api_key = env!("TAVILY_API_KEY", :string, nil)

if tavily_api_key && config_env() != :test do
  config :lincoln, :tavily,
    api_key: tavily_api_key,
    search_depth: env!("TAVILY_SEARCH_DEPTH", :string, "basic"),
    max_results: env!("TAVILY_MAX_RESULTS", :integer, 5)

  config :lincoln, :search_adapter, Lincoln.MCP.SearchClient.Tavily
end

# Python ML Service URL
ml_service_url = env!("ML_SERVICE_URL", :string, nil)

if config_env() == :prod do
  unless ml_service_url do
    raise """
    environment variable ML_SERVICE_URL is missing.
    This should point to your Python ML service (e.g., http://localhost:8000)
    """
  end
end

if ml_service_url do
  config :lincoln, :embeddings, service_url: ml_service_url
end

if config_env() == :prod do
  database_url =
    env!("DATABASE_URL", :string, nil) ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if env!("ECTO_IPV6", :boolean, false), do: [:inet6], else: []

  config :lincoln, Lincoln.Repo,
    # ssl: true,
    url: database_url,
    pool_size: env!("POOL_SIZE", :integer, 10),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    env!("SECRET_KEY_BASE", :string, nil) ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = env!("PHX_HOST", :string, "example.com")

  config :lincoln, :dns_cluster_query, env!("DNS_CLUSTER_QUERY", :string, nil)

  config :lincoln, LincolnWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
