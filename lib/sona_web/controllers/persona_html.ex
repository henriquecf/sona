# Dev-only (D-005): compiled only with dev routes, so it never ships to production.
if Application.compile_env(:sona, :dev_routes) do
  defmodule SonaWeb.PersonaHTML do
    use SonaWeb, :html

    embed_templates "persona_html/*"
  end
end
