# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :lincoln,
  ecto_repos: [Lincoln.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :lincoln, LincolnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LincolnWeb.ErrorHTML, json: LincolnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Lincoln.PubSub,
  live_view: [signing_salt: "naLxtQFN"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :lincoln, Lincoln.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  lincoln: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  lincoln: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :lincoln, Oban,
  repo: Lincoln.Repo,
  queues: [
    default: 10,
    reflection: 2,
    curiosity: 2,
    investigation: 5,
    maintenance: 2
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Reflection cycle every 6 hours
       {"0 */6 * * *", Lincoln.Workers.ReflectionWorker},
       # Curiosity check every hour
       {"0 * * * *", Lincoln.Workers.CuriosityWorker},
       # Belief maintenance daily at 3am
       {"0 3 * * *", Lincoln.Workers.BeliefMaintenanceWorker}
     ]}
  ]

# Lincoln-specific configuration
config :lincoln, :embeddings,
  service_url: "http://localhost:8000",
  model: "all-MiniLM-L6-v2",
  dimensions: 384

config :lincoln, :llm,
  provider: :anthropic,
  model: "claude-sonnet-4-20250514",
  max_tokens: 4096

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
