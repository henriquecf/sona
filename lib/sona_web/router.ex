defmodule SonaWeb.Router do
  use SonaWeb, :router

  import SonaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SonaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", SonaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sona, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SonaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Sign in as any seeded team member, for demos (D-005).
    scope "/dev", SonaWeb do
      pipe_through :browser

      get "/personas", PersonaController, :index
      post "/personas/:id", PersonaController, :create
    end
  end

  ## Authentication routes

  scope "/", SonaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SonaWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/no-team", NoTeamLive, :show
    end

    # Company routes: an active team member is required (D-003).
    live_session :require_team_member,
      on_mount: [
        {SonaWeb.UserAuth, :require_authenticated},
        {SonaWeb.UserAuth, :require_team_member}
      ] do
      live "/", HomeLive, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", SonaWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SonaWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
