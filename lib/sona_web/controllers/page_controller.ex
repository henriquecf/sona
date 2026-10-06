defmodule SonaWeb.PageController do
  use SonaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
