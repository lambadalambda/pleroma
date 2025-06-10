# Pleroma: A lightweight social networking server
# Copyright © 2017-2025 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ActivityPubUploadTrackingTest do
  use Pleroma.DataCase
  use Oban.Testing, repo: Pleroma.Repo

  alias Pleroma.Upload.UserUpload
  alias Pleroma.Web.ActivityPub.ActivityPub

  import Pleroma.Factory
  import Mox

  setup :verify_on_exit!

  describe "upload tracking" do
    setup do
      Tesla.Mock.mock(fn env -> apply(HttpRequestMock, :request, [env]) end)

      # Setup temp directory for uploads
      File.mkdir_p!("test/tmp/")
      on_exit(fn -> File.rm_rf!("test/tmp/") end)

      # Setup config mocks for Upload module
      Mox.stub_with(Pleroma.UnstubbedConfigMock, Pleroma.Test.StaticConfig)

      :ok
    end

    test "creates UserUpload record when uploading media" do
      user = insert(:user)

      file_path = "test/fixtures/image.jpg"
      File.cp!(file_path, "test/tmp/image_copy.jpg")

      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/image_copy.jpg",
        filename: "an_image.jpg"
      }

      assert {:ok, object} = ActivityPub.upload(file, actor: user.ap_id)

      # Check that a UserUpload record was created
      user_upload = UserUpload.get_by_user_and_object(user.id, object.id)
      assert user_upload
      assert user_upload.user_id == user.id
      assert user_upload.object_id == object.id
      assert user_upload.file_path
      assert user_upload.file_size > 0
      assert user_upload.content_type == "image/jpeg"
      # Not yet used in a post
      assert user_upload.activity_id == nil
    end

    test "does not create UserUpload record when actor is not provided" do
      file_path = "test/fixtures/image.jpg"
      File.cp!(file_path, "test/tmp/image_copy2.jpg")

      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/image_copy2.jpg",
        filename: "an_image.jpg"
      }

      assert {:ok, _object} = ActivityPub.upload(file)

      # No UserUpload records should exist
      assert [] == Repo.all(UserUpload)
    end

    test "extracts file path correctly from upload URL" do
      user = insert(:user)

      file_path = "test/fixtures/image.jpg"
      File.cp!(file_path, "test/tmp/image_copy3.jpg")

      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/image_copy3.jpg",
        filename: "an_image.jpg"
      }

      assert {:ok, object} = ActivityPub.upload(file, actor: user.ap_id)

      user_upload = UserUpload.get_by_user_and_object(user.id, object.id)

      # The file_path should be relative, not include the full URL
      refute String.starts_with?(user_upload.file_path, "http")

      # It should match the path portion of the URL
      [%{"href" => url}] = object.data["url"]
      url_path = URI.parse(url).path
      # Remove /media/ prefix if present
      expected_path = String.replace_prefix(url_path, "/media/", "")
      assert user_upload.file_path == expected_path
    end

    test "handles deduplication correctly with Dedupe filter" do
      clear_config([Pleroma.Upload, :filters], [Pleroma.Upload.Filter.Dedupe])

      user1 = insert(:user)
      user2 = insert(:user)

      file_path = "test/fixtures/image.jpg"

      # First upload
      File.cp!(file_path, "test/tmp/dedup1.jpg")

      file1 = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/dedup1.jpg",
        filename: "test_image.jpg"
      }

      assert {:ok, object1} = ActivityPub.upload(file1, actor: user1.ap_id)
      user_upload1 = UserUpload.get_by_user_and_object(user1.id, object1.id)

      # Second user uploads the same file
      File.cp!(file_path, "test/tmp/dedup2.jpg")

      file2 = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/dedup2.jpg",
        filename: "test_image.jpg"
      }

      assert {:ok, object2} = ActivityPub.upload(file2, actor: user2.ap_id)
      user_upload2 = UserUpload.get_by_user_and_object(user2.id, object2.id)

      # Objects should be different (each user gets their own Object)
      assert object1.id != object2.id

      # But file paths should be the same (deduplication worked)
      assert user_upload1.file_path == user_upload2.file_path

      # And they should be different UserUpload records
      assert user_upload1.id != user_upload2.id
      assert user_upload1.user_id != user_upload2.user_id
    end

    test "stores description when provided" do
      user = insert(:user)

      file_path = "test/fixtures/image.jpg"
      File.cp!(file_path, "test/tmp/image_desc.jpg")

      file = %Plug.Upload{
        content_type: "image/jpeg",
        path: "test/tmp/image_desc.jpg",
        filename: "an_image.jpg"
      }

      assert {:ok, object} = ActivityPub.upload(file, actor: user.ap_id, description: "My photo")

      user_upload = UserUpload.get_by_user_and_object(user.id, object.id)
      assert user_upload.description == "My photo"
    end
  end
end
