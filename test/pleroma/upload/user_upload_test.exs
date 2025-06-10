# Pleroma: A lightweight social networking server
# Copyright © 2017-2025 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.UserUploadTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Upload.UserUpload

  import Pleroma.Factory

  describe "schema" do
    test "has expected fields" do
      upload = %UserUpload{}

      assert Map.has_key?(upload, :user_id)
      assert Map.has_key?(upload, :object_id)
      assert Map.has_key?(upload, :activity_id)
      assert Map.has_key?(upload, :file_path)
      assert Map.has_key?(upload, :file_size)
      assert Map.has_key?(upload, :content_type)
      assert Map.has_key?(upload, :description)
      assert Map.has_key?(upload, :inserted_at)
      assert Map.has_key?(upload, :updated_at)
    end
  end

  describe "changeset/2" do
    setup do
      user = insert(:user)
      note = insert(:note, user: user)
      activity = insert(:note_activity, user: user, note: note)

      # Create a media object
      media_object = insert(:attachment)

      valid_attrs = %{
        user_id: user.id,
        object_id: media_object.id,
        activity_id: activity.id,
        file_path:
          "e3/03/97/e30397b58d226d6583ab5b8b3c5defb0c682bda5c31ef07a9f57c1c4986e3781.jpg",
        file_size: 102_400,
        content_type: "image/jpeg",
        description: "A test image"
      }

      %{user: user, media_object: media_object, activity: activity, valid_attrs: valid_attrs}
    end

    test "creates a valid changeset with required fields", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :user_id) == attrs.user_id
      assert get_change(changeset, :object_id) == attrs.object_id
      assert get_change(changeset, :activity_id) == attrs.activity_id
      assert get_change(changeset, :file_path) == attrs.file_path
      assert get_change(changeset, :file_size) == attrs.file_size
      assert get_change(changeset, :content_type) == attrs.content_type
      assert get_change(changeset, :description) == attrs.description
    end

    test "requires user_id", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :user_id))

      refute changeset.valid?
      assert errors_on(changeset).user_id == ["can't be blank"]
    end

    test "requires object_id", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :object_id))

      refute changeset.valid?
      assert errors_on(changeset).object_id == ["can't be blank"]
    end

    test "requires file_path", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :file_path))

      refute changeset.valid?
      assert errors_on(changeset).file_path == ["can't be blank"]
    end

    test "requires file_size", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :file_size))

      refute changeset.valid?
      assert errors_on(changeset).file_size == ["can't be blank"]
    end

    test "validates file_size is positive", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, %{attrs | file_size: 0})

      refute changeset.valid?
      assert errors_on(changeset).file_size == ["must be greater than 0"]
    end

    test "activity_id is optional", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :activity_id))

      assert changeset.valid?
    end

    test "description is optional", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :description))

      assert changeset.valid?
    end

    test "content_type is optional", %{valid_attrs: attrs} do
      changeset = UserUpload.changeset(%UserUpload{}, Map.delete(attrs, :content_type))

      assert changeset.valid?
    end

    test "enforces unique constraint on user_id and object_id", %{valid_attrs: attrs} do
      # First insert
      {:ok, _} =
        %UserUpload{}
        |> UserUpload.changeset(attrs)
        |> Repo.insert()

      # Attempt duplicate
      changeset = UserUpload.changeset(%UserUpload{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset).user_id == ["has already been taken"]
    end
  end

  describe "create/1" do
    setup do
      user = insert(:user)
      media_object = insert(:attachment)

      valid_attrs = %{
        user_id: user.id,
        object_id: media_object.id,
        file_path:
          "e3/03/97/e30397b58d226d6583ab5b8b3c5defb0c682bda5c31ef07a9f57c1c4986e3781.jpg",
        file_size: 102_400,
        content_type: "image/jpeg"
      }

      %{valid_attrs: valid_attrs}
    end

    test "creates a user upload with valid attributes", %{valid_attrs: attrs} do
      assert {:ok, upload} = UserUpload.create(attrs)

      assert upload.user_id == attrs.user_id
      assert upload.object_id == attrs.object_id
      assert upload.file_path == attrs.file_path
      assert upload.file_size == attrs.file_size
      assert upload.content_type == attrs.content_type
    end

    test "returns error with invalid attributes" do
      assert {:error, changeset} = UserUpload.create(%{})
      refute changeset.valid?
    end
  end

  describe "get_by_user_and_object/2" do
    setup do
      user = insert(:user)
      media_object = insert(:attachment)

      {:ok, upload} =
        UserUpload.create(%{
          user_id: user.id,
          object_id: media_object.id,
          file_path: "test/path/image.jpg",
          file_size: 1024,
          content_type: "image/jpeg"
        })

      %{user: user, media_object: media_object, upload: upload}
    end

    test "finds upload by user and object", %{
      user: user,
      media_object: media_object,
      upload: upload
    } do
      found = UserUpload.get_by_user_and_object(user.id, media_object.id)

      assert found.id == upload.id
    end

    test "returns nil when not found", %{user: user} do
      other_object = insert(:attachment)

      assert nil == UserUpload.get_by_user_and_object(user.id, other_object.id)
    end
  end

  describe "get_by_user/2" do
    setup do
      user = insert(:user)
      other_user = insert(:user)

      uploads =
        for i <- 1..5 do
          media_object = insert(:attachment)

          {:ok, upload} =
            UserUpload.create(%{
              user_id: user.id,
              object_id: media_object.id,
              file_path: "test/path/image#{i}.jpg",
              file_size: 1024 * i,
              content_type: "image/jpeg"
            })

          upload
        end

      # Create upload for other user
      other_object = insert(:attachment)

      {:ok, _other_upload} =
        UserUpload.create(%{
          user_id: other_user.id,
          object_id: other_object.id,
          file_path: "test/path/other.jpg",
          file_size: 2048,
          content_type: "image/jpeg"
        })

      %{user: user, other_user: other_user, uploads: uploads}
    end

    test "returns all uploads for a user", %{user: user, uploads: uploads} do
      found = UserUpload.get_by_user(user.id)

      assert length(found) == 5
      assert Enum.all?(found, &(&1.user_id == user.id))
      assert MapSet.new(found, & &1.id) == MapSet.new(uploads, & &1.id)
    end

    test "supports pagination", %{user: user} do
      page1 = UserUpload.get_by_user(user.id, limit: 2, offset: 0)
      page2 = UserUpload.get_by_user(user.id, limit: 2, offset: 2)
      page3 = UserUpload.get_by_user(user.id, limit: 2, offset: 4)

      assert length(page1) == 2
      assert length(page2) == 2
      assert length(page3) == 1

      # Ensure no duplicates
      all_ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(Enum.uniq(all_ids)) == 5
    end

    test "returns empty list for user with no uploads" do
      new_user = insert(:user)

      assert [] == UserUpload.get_by_user(new_user.id)
    end
  end

  describe "get_by_file_path/1" do
    setup do
      # Simulate deduplicated file - same path for multiple users
      file_path = "e3/03/97/e30397b58d226d6583ab5b8b3c5defb0c682bda5c31ef07a9f57c1c4986e3781.jpg"

      users = for _ <- 1..3, do: insert(:user)

      uploads =
        for user <- users do
          media_object = insert(:attachment)

          {:ok, upload} =
            UserUpload.create(%{
              user_id: user.id,
              object_id: media_object.id,
              file_path: file_path,
              file_size: 102_400,
              content_type: "image/jpeg"
            })

          upload
        end

      %{file_path: file_path, uploads: uploads}
    end

    test "finds all uploads with the same file path", %{file_path: file_path, uploads: uploads} do
      found = UserUpload.get_by_file_path(file_path)

      assert length(found) == 3
      assert MapSet.new(found, & &1.id) == MapSet.new(uploads, & &1.id)
    end

    test "returns empty list for unknown path" do
      assert [] == UserUpload.get_by_file_path("unknown/path/file.jpg")
    end
  end

  describe "count_by_file_path/1" do
    test "counts number of users referencing a file path" do
      file_path = "e3/03/97/e30397b58d226d6583ab5b8b3c5defb0c682bda5c31ef07a9f57c1c4986e3781.jpg"

      # Create uploads with same path for multiple users
      for _ <- 1..3 do
        user = insert(:user)
        media_object = insert(:attachment)

        {:ok, _} =
          UserUpload.create(%{
            user_id: user.id,
            object_id: media_object.id,
            file_path: file_path,
            file_size: 102_400,
            content_type: "image/jpeg"
          })
      end

      assert UserUpload.count_by_file_path(file_path) == 3
    end

    test "returns 0 for unknown path" do
      assert UserUpload.count_by_file_path("unknown/path") == 0
    end
  end

  describe "delete/1" do
    setup do
      user = insert(:user)
      media_object = insert(:attachment)

      {:ok, upload} =
        UserUpload.create(%{
          user_id: user.id,
          object_id: media_object.id,
          file_path: "test/path/image.jpg",
          file_size: 102_400,
          content_type: "image/jpeg"
        })

      %{upload: upload}
    end

    test "deletes the upload", %{upload: upload} do
      assert {:ok, _} = UserUpload.delete(upload)
      assert nil == UserUpload.get_by_user_and_object(upload.user_id, upload.object_id)
    end

    test "returns the deleted upload", %{upload: upload} do
      assert {:ok, deleted} = UserUpload.delete(upload)
      assert deleted.id == upload.id
      assert deleted.file_path == upload.file_path
    end
  end

  describe "delete_by_user_and_object/2" do
    setup do
      user = insert(:user)
      media_object = insert(:attachment)

      {:ok, upload} =
        UserUpload.create(%{
          user_id: user.id,
          object_id: media_object.id,
          file_path: "test/path/image.jpg",
          file_size: 102_400,
          content_type: "image/jpeg"
        })

      %{user: user, media_object: media_object, upload: upload}
    end

    test "deletes upload by user and object ids", %{
      user: user,
      media_object: media_object,
      upload: upload
    } do
      assert {:ok, deleted} = UserUpload.delete_by_user_and_object(user.id, media_object.id)
      assert deleted.id == upload.id
      assert nil == UserUpload.get_by_user_and_object(user.id, media_object.id)
    end

    test "returns error when upload not found", %{user: user} do
      other_object = insert(:attachment)
      assert {:error, :not_found} = UserUpload.delete_by_user_and_object(user.id, other_object.id)
    end
  end
end
