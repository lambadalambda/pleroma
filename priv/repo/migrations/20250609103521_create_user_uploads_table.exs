defmodule Pleroma.Repo.Migrations.CreateUserUploadsTable do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:user_uploads) do
      add(:user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false)
      add(:object_id, references(:objects, on_delete: :delete_all), null: false)
      add(:activity_id, references(:activities, type: :uuid, on_delete: :delete_all))
      add(:file_path, :text, null: false)
      add(:file_size, :bigint, null: false)
      add(:content_type, :string)
      add(:description, :text)

      timestamps()
    end

    # Unique constraint and also serves as index for user_id queries
    create_if_not_exists(unique_index(:user_uploads, [:user_id, :object_id]))

    # For deduplication - finding all references to same file
    create_if_not_exists(index(:user_uploads, [:file_path]))
  end
end
