defmodule Sona.Companies.CompanyValue do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Companies.Company

  schema "company_values" do
    field :name, :string
    field :description, :string

    belongs_to :company, Company

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(company_value, attrs) do
    company_value
    |> cast(attrs, [:name, :description])
    |> validate_required([:name, :description])
    |> foreign_key_constraint(:company_id)
    |> unique_constraint(:name, name: :company_values_company_id_name_index)
  end
end
