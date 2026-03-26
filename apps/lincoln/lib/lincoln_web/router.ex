defmodule LincolnWeb.Router do
  use LincolnWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {LincolnWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", LincolnWeb do
    pipe_through(:browser)

    # Dashboard is the main page
    live("/", DashboardLive)

    # Chat interface
    live("/chat", ChatLive, :index)
    live("/chat/:id", ChatLive, :show)

    # Beliefs
    live("/beliefs", BeliefsLive, :index)
    live("/beliefs/:id", BeliefsLive, :show)

    # Questions
    live("/questions", QuestionsLive, :index)
    live("/questions/:id", QuestionsLive, :show)

    # Memories
    live("/memories", MemoriesLive, :index)
    live("/memories/:id", MemoriesLive, :show)

    # Keep the old page controller for reference
    get("/welcome", PageController, :home)
  end

  # API routes for external agent interaction
  scope "/api", LincolnWeb.API do
    pipe_through(:api)

    # Agent status
    get("/agent", AgentController, :show)

    # Beliefs
    get("/beliefs", AgentController, :list_beliefs)
    post("/beliefs", AgentController, :create_belief)
    get("/beliefs/:id", AgentController, :get_belief)

    # Questions
    get("/questions", AgentController, :list_questions)
    post("/questions", AgentController, :ask_question)
    get("/questions/:id", AgentController, :get_question)
    post("/questions/:id/findings", AgentController, :create_finding)

    # Memories
    get("/memories", AgentController, :list_memories)
    post("/memories", AgentController, :create_memory)
    get("/memories/:id", AgentController, :get_memory)

    # Convenience endpoints
    post("/observations", AgentController, :record_observation)
    post("/reflections", AgentController, :record_reflection)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:lincoln, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: LincolnWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
