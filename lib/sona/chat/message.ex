defmodule Sona.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sona.Chat.Conversation
  alias Sona.Companies.TeamMember

  schema "messages" do
    field :body, :string

    belongs_to :conversation, Conversation
    belongs_to :author, TeamMember

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for what the author writes. The conversation and author are
  set by `Sona.Chat` from the scope, never cast.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> validate_required([:body])
    # Code points, to match the database's char_length.
    |> validate_length(:body, max: 4000, count: :codepoints)
    |> check_constraint(:body, name: :body_length)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:author_id)
  end
end
