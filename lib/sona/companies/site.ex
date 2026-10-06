defmodule Sona.Companies.Site do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Companies.Company

  schema "sites" do
    field :name, :string
    belongs_to :company, Company

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:name, name: :sites_company_id_name_index)
  end
end
