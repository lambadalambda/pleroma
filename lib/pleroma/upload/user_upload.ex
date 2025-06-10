# Pleroma: A lightweight social networking server
# Copyright © 2017-2025 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.UserUpload do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Object
  alias Pleroma.Activity

  schema "user_uploads" do
    belongs_to(:user, User, type: FlakeId.Ecto.CompatType)
    belongs_to(:object, Object)
    belongs_to(:activity, Activity, type: FlakeId.Ecto.CompatType)

    field(:file_path, :string)
    field(:file_size, :integer)
    field(:content_type, :string)
    field(:description, :string)

    timestamps()
  end

  @required_fields [:user_id, :object_id, :file_path, :file_size]
  @optional_fields [:activity_id, :content_type, :description]

  def changeset(user_upload \\ %__MODULE__{}, attrs) do
    user_upload
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:file_size, greater_than: 0)
    |> unique_constraint(:user_id, name: :user_uploads_user_id_object_id_index)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:object_id)
    |> foreign_key_constraint(:activity_id)
  end

  @doc """
  Creates a new user upload record.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user upload by user_id and object_id.
  """
  def get_by_user_and_object(user_id, object_id) do
    from(u in __MODULE__,
      where: u.user_id == ^user_id and u.object_id == ^object_id
    )
    |> Repo.one()
  end

  @doc """
  Gets all uploads for a user with optional pagination.
  """
  def get_by_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(u in __MODULE__,
      where: u.user_id == ^user_id,
      order_by: [desc: u.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Gets all uploads with the same file path (for deduplication checks).
  """
  def get_by_file_path(file_path) do
    from(u in __MODULE__,
      where: u.file_path == ^file_path,
      order_by: [desc: u.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Counts how many uploads reference the same file path.
  """
  def count_by_file_path(file_path) do
    from(u in __MODULE__,
      where: u.file_path == ^file_path,
      select: count(u.id)
    )
    |> Repo.one()
  end

  @doc """
  Deletes a user upload record.
  """
  def delete(%__MODULE__{} = user_upload) do
    Repo.delete(user_upload)
  end

  @doc """
  Deletes a user upload by user_id and object_id.
  """
  def delete_by_user_and_object(user_id, object_id) do
    case get_by_user_and_object(user_id, object_id) do
      nil -> {:error, :not_found}
      upload -> delete(upload)
    end
  end
end
