# Media Management Implementation Plan

## Overview

This document outlines the implementation plan for the Media Management feature as part of the NLNet-funded development work. The goal is to enable users to view and manage all media they have uploaded to their Pleroma instance.

**NLNet Requirement**: "Media management (€1000) - Being able to see all the stuff you ever uploaded and wipe it"

## Background

Currently, Pleroma handles media uploads well but lacks user-facing management features. Users cannot:
- View a list of all their uploads
- Delete old or unwanted media
- See how much storage they're using
- Bulk manage their media

This implementation will address these gaps while integrating seamlessly with Pleroma's existing architecture.

## Technical Analysis

### Current State

1. **Upload System**
   - Uploads are stored as `Object` records in the database
   - Multiple storage backends supported (Local, S3, IPFS)
   - Rich metadata stored including dimensions, blurhash, content type
   - Existing cleanup workers for orphaned attachments

2. **API Structure**
   - Mastodon-compatible media endpoints exist
   - No user-facing media management endpoints
   - Admin has some media proxy management capabilities

3. **Database Schema**
   - Objects table uses JSONB for flexible data storage
   - No dedicated indexes for user media queries
   - Attachments linked through ActivityPub object structure

### Key Architectural Insights

1. **ActivityPub Data Model**
   - Activities represent actions (Create, Update, Delete, etc.)
   - Objects contain the actual content (posts, media, etc.)
   - Media attachments are Objects referenced in the attachments array of post Objects
   - Create activities reference the Object they create
   - Activities have an actor (the user who performed the action)

2. **Upload Filters and Deduplication**
   - Upload filters are applied in sequence during upload processing
   - The Dedupe filter (when enabled) saves files as `{sha256_hash}.{extension}`
   - File paths with Dedupe: `e3/03/97/{full_hash}.jpg` (sharded by first 6 chars)
   - Without Dedupe: UUID-based filenames, each upload is unique
   - The upload system already handles the complexity of deduplication

3. **Object and Activity Relationships**
   - A media Object can be referenced by multiple Activities
   - The same media can appear in multiple posts by the same user
   - Activities are never updated in-place; changes create Update activities
   - Deleting content requires federating Update or Delete activities

4. **Storage Architecture**
   - File path is stored in the Object's data as the URL
   - The URL path is relative to the upload base URL
   - Local storage example: `/media/e3/03/97/hash.jpg` → file at `uploads/e3/03/97/hash.jpg`
   - Multiple uploaders (Local, S3, IPFS) all follow the same path conventions
   - Physical file deletion is handled by the uploader module
   - Need to extract relative path from full URL for storage tracking

5. **Performance Considerations**
   - JSONB queries on large tables can be slow
   - Adding indexes to existing large tables can cause downtime
   - New tables with proper indexes are preferred over modifying existing ones
   - Direct foreign key relationships are much faster than JSONB searches

## Implementation Design

### Important Implementation Notes

1. **Media Upload Flow**
   - User uploads file → Create activity is generated → Upload filters run → Object is created
   - The Object contains the media metadata and file path
   - The Create activity references this Object
   - Both are saved before the upload completes

2. **Finding Media in Posts**
   - Post Objects have `attachment` field containing array of media Objects
   - Media Objects have `type: "Document"` (or "Image", "Video", etc.)
   - Can search via: `WHERE data->'attachment' @> '[{"id": "object_id"}]'`
   - But direct activity_id reference is much faster

3. **Federation Considerations**
   - Modifying a post requires sending Update activity to followers
   - The Update must contain the complete modified Object
   - Remote instances will update their cached version
   - Must preserve all other fields when removing attachments

4. **Edge Cases to Handle**
   - Media used in user's avatar/banner (check User's avatar/banner fields)
   - Media in scheduled posts (check ScheduledActivity)
   - Media in drafts (if implemented)
   - Media referenced but file already deleted (handle gracefully)

### Test-Driven Development Approach

This implementation will follow strict TDD principles:
1. Write failing tests for each feature before implementation
2. Implement minimal code to make tests pass
3. Refactor while keeping tests green
4. Maintain high test coverage (>90%)

### API Endpoints

All endpoints will be under `/api/v1/pleroma/media/`:

#### List User Media
```
GET /api/v1/pleroma/media
```
**Parameters:**
- `page` (integer): Page number for pagination
- `page_size` (integer): Items per page (max: 50, default: 20)
- `type` (string): Filter by media type (image/video/audio/document)
- `date_from` (datetime): Filter media uploaded after this date
- `date_to` (datetime): Filter media uploaded before this date
- `min_size` (integer): Minimum file size in bytes
- `max_size` (integer): Maximum file size in bytes

**Response:**
```json
{
  "items": [
    {
      "id": "108775885754745935",
      "url": "https://example.com/media/abcd1234.jpg",
      "preview_url": "https://example.com/media/abcd1234_preview.jpg",
      "type": "image",
      "description": "A cat photo",
      "blurhash": "UFBWY:9F00WB9F",
      "created_at": "2024-01-15T10:30:00Z",
      "size": 524288,
      "dimensions": {
        "width": 1920,
        "height": 1080
      },
      "used_in": {
        "posts": 2,
        "profile": false
      }
    }
  ],
  "pagination": {
    "total": 150,
    "page": 1,
    "page_size": 20,
    "total_pages": 8
  }
}
```

#### Get Media Details
```
GET /api/v1/pleroma/media/:id
```
Returns detailed information about a specific media upload.

#### Delete Media
```
DELETE /api/v1/pleroma/media/:id
```
**Response:** 204 No Content on success

**Behavior:**
1. Find all posts by the user that include this media
2. Remove the attachment from each post
3. Send Update activities to federate the changes
4. Remove the user's association with the upload
5. Delete the physical file if no other users reference it
6. Update any cached post representations

#### Bulk Delete Media
```
POST /api/v1/pleroma/media/delete_bulk
```
**Request Body:**
```json
{
  "ids": ["id1", "id2", "id3"],
  "older_than": "2023-01-01T00:00:00Z",
  "type": "image",
  "force": false
}
```
**Response:**
```json
{
  "deleted": 15,
  "failed": 2,
  "errors": [
    {
      "id": "108775885754745935",
      "error": "Media is used in active posts"
    }
  ]
}
```

#### Media Statistics
```
GET /api/v1/pleroma/media/stats
```
**Response:**
```json
{
  "total_count": 150,
  "total_size": 157286400,
  "by_type": {
    "image": { "count": 120, "size": 125829120 },
    "video": { "count": 20, "size": 26214400 },
    "audio": { "count": 10, "size": 5242880 }
  },
  "by_month": [
    {
      "month": "2024-01",
      "count": 45,
      "size": 47185920
    }
  ]
}
```

### Backend Architecture

#### New Modules

1. **`Pleroma.Web.PleromaAPI.MediaController`**
   - Handles HTTP requests
   - Parameter validation
   - Response formatting

2. **`Pleroma.Upload.UserUpload`**
   - Schema for user_uploads table
   - Changeset validations
   - Query helpers for user uploads
   - Deduplication logic
   - Reference counting

3. **`Pleroma.Upload.UserMedia`**
   - Core business logic
   - Query user's uploads from UserUpload
   - Find all activities using a media object
   - Validation of ownership
   - Coordinate media deletion across activities
   - Integration with storage backends

5. **`Pleroma.Upload.MediaStats`**
   - Calculate usage statistics
   - Cache management for performance
   - Aggregation queries across new tables

6. **`Pleroma.Workers.MediaDeletionWorker`**
   - Background processing for bulk deletions
   - Update posts to remove attachments
   - Federate Update activities for modified posts
   - Safe cleanup with deduplication checks
   - Physical file deletion only when no references remain
   - Progress tracking

7. **`Pleroma.Workers.MediaBackfillWorker`**
   - Process historical uploads for backfilling
   - Batch processing to avoid overwhelming the system
   - Resume capability for interrupted jobs

8. **Mix Tasks**
   - `mix pleroma.media.backfill` - Backfill historical upload associations
   - `mix pleroma.media.stats` - Display media statistics
   - `mix pleroma.media.cleanup` - Clean orphaned media files

#### Backfill Process

The backfill process will work as follows:

1. **Determine Starting Point**
   - Find the oldest entry in user_uploads table
   - If empty, process all local activities
   - If populated, process activities older than the oldest upload

2. **Batch Processing**
   - Process activities in batches of 1000
   - For each local Create activity with attachments:
     a. Extract media objects from the activity
     b. Extract file_path from the object's URL
     c. Create user_upload records with activity_id
   - Track progress in a dedicated table
   - Allow resuming from last processed ID

3. **Safety Measures**
   - Dry run mode to preview changes
   - Configurable batch size
   - Rate limiting to prevent overload
   - Progress reporting
   - Rollback capability

#### Database Schema

1. **New Table**

   ```sql
   -- Associates users with their uploads
   CREATE TABLE user_uploads (
     id BIGSERIAL PRIMARY KEY,
     user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
     object_id BIGINT NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
     activity_id BIGINT REFERENCES activities(id) ON DELETE CASCADE, -- The Create activity for this upload
     file_path TEXT NOT NULL, -- With Dedupe filter, path contains the hash
     file_size BIGINT NOT NULL,
     content_type VARCHAR(255),
     description TEXT,
     inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
     updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
     UNIQUE(user_id, object_id)
   );
   
   CREATE INDEX user_uploads_user_id_idx ON user_uploads(user_id);
   CREATE INDEX user_uploads_object_id_idx ON user_uploads(object_id);
   CREATE INDEX user_uploads_activity_id_idx ON user_uploads(activity_id);
   CREATE INDEX user_uploads_file_path_idx ON user_uploads(file_path); -- For dedup checks
   CREATE INDEX user_uploads_inserted_at_idx ON user_uploads(inserted_at);
   ```
   
   **Why only one table?**
   - Activities already track which user posted (actor)
   - Objects already contain attachments array
   - Storing activity_id avoids slow JSONB queries
   - Direct lookup of where media is used
   - No need for a separate post_uploads table

2. **Deduplication Support**
   - When Dedupe filter is enabled, file_path contains the content hash
   - Multiple users uploading the same file will have the same file_path
   - Reference counting via counting user_uploads with same file_path
   - Only delete physical file when no other user_uploads reference that path
   - Each user maintains their own upload record even for deduplicated files
   
   **Note**: If Dedupe filter is not enabled, each upload gets a unique path (usually UUID-based), 
   so the same content uploaded multiple times will create multiple files. In this case, 
   each file can be safely deleted when its user_upload record is removed.

3. **Migration Strategy**
   - Tables created empty - no automatic backfill
   - New uploads tracked immediately after deployment
   - Historical data populated via mix task
   - No performance impact on existing large tables

4. **Deletion Flow**
   - When a user deletes media:
     a. Look up the user_upload record
     b. Find all activities where this media is used (via activity_id and by searching attachments)
     c. Update each activity to remove the attachment
     d. Federate Update activities for each modified post
     e. Delete the user_upload record
     f. Check if any other user_uploads have the same file_path
     g. Only delete physical file if no other references exist

### Security Considerations

1. **Authentication**: All endpoints require user authentication
2. **Authorization**: Users can only manage their own uploads
3. **Rate Limiting**: 
   - List: 60 requests/minute
   - Delete: 30 requests/minute
   - Bulk delete: 5 requests/minute
4. **Audit Logging**: All deletions logged for security
5. **Soft Delete**: Optional grace period before permanent deletion

### Performance Optimizations

1. **Caching**
   - Cache user media stats for 5 minutes
   - Cache frequently accessed media lists
   - Use ETS for in-memory caching

2. **Query Optimization**
   - Use cursor-based pagination for large datasets
   - Limit default page size
   - Add query hints for PostgreSQL

3. **Background Processing**
   - Bulk operations processed asynchronously
   - Progress updates via websocket/polling
   - Automatic retry with exponential backoff

## Implementation Phases

### Phase 1: Database Foundation (TDD)
- [ ] Write tests for UserUpload schema and changesets
- [ ] Implement UserUpload module
- [ ] Create database migration for user_uploads table
- [ ] Write tests for deduplication logic (file_path based)
- [ ] Implement reference counting via file_path queries

### Phase 2: Core Upload Tracking
- [ ] Write tests for upload creation hooks
- [ ] Modify Upload module to create UserUpload records
- [ ] Write tests for activity association
- [ ] Hook into CommonAPI to store activity_id in UserUpload
- [ ] Write tests for reference counting
- [ ] Implement reference counting logic

### Phase 3: Query and API Layer
- [ ] Write tests for UserMedia queries
- [ ] Implement UserMedia module with ownership validation
- [ ] Write controller tests for list endpoint
- [ ] Implement MediaController list endpoint
- [ ] Write controller tests for delete endpoint
- [ ] Implement delete with deduplication safety

### Phase 4: Bulk Operations and Stats
- [ ] Write tests for bulk delete operations
- [ ] Implement MediaDeletionWorker
- [ ] Write tests for media statistics
- [ ] Implement MediaStats module
- [ ] Write tests for stats caching
- [ ] Add caching layer

### Phase 5: Historical Data Migration
- [ ] Write tests for backfill worker
- [ ] Implement MediaBackfillWorker
- [ ] Write tests for mix task
- [ ] Create mix pleroma.media.backfill task
- [ ] Add progress tracking and resumability
- [ ] Test with various data scenarios

### Phase 6: Integration and Polish
- [ ] Integration tests with all storage backends
- [ ] Performance testing with large datasets
- [ ] Add Prometheus metrics
- [ ] API documentation
- [ ] Admin configuration guide
- [ ] Create troubleshooting guide

## Testing Strategy

### Test-First Development
Every feature will be developed using TDD:
1. Write failing test describing desired behavior
2. Write minimal code to pass the test
3. Refactor for clarity and performance
4. Ensure all tests remain green

### Unit Tests
- UserUpload and PostUpload schemas and changesets
- Deduplication logic and reference counting
- Media deletion with post updates
- Federation of Update activities
- UserMedia query functions
- MediaStats calculations
- Authorization logic
- Cache invalidation

### Integration Tests
- Full API flow with different storage backends
- Media deletion updating posts and federating
- Deduplication scenarios with multiple users
- Bulk operations with large datasets
- Error handling and edge cases
- Rate limiting behavior
- Backfill process with various data patterns

### Performance Tests
- Query performance with 10k+ uploads
- Bulk deletion performance
- Federation performance for mass updates
- Cache effectiveness
- Database index usage
- Backfill performance on large instances

## Rollout Plan

1. **Beta Testing**
   - Deploy to test instance
   - Limited rollout to volunteer instances
   - Gather performance metrics

2. **Gradual Rollout**
   - Enable for new uploads first
   - Backfill existing media data
   - Monitor system impact

3. **Full Release**
   - Documentation release
   - Announcement to instance admins
   - PleromaFE integration

## Success Metrics

- Users can view all their uploads
- Deletion success rate > 99%
- Query response time < 200ms for typical usage
- No significant impact on instance performance
- Positive user feedback

## Future Enhancements

- Media organization (albums/collections)
- Advanced search (by text in images, facial recognition opt-in)
- Storage quota management
- Media sharing between users
- Automatic cleanup policies
- Export/import functionality

## Dependencies

- Pleroma 2.6.0 or later
- PostgreSQL 11+ (for JSONB indexing)
- Elixir 1.14+
- Storage backend (Local/S3/IPFS)

## Configuration

New configuration options in `config.exs`:

```elixir
config :pleroma, :media_management,
  enabled: true,
  soft_delete_days: 7,
  max_bulk_delete: 100,
  stats_cache_ttl: 300,
  enable_audit_log: true
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance degradation | High | Extensive caching, query optimization |
| Accidental data loss | High | Soft delete, confirmation dialogs |
| Storage backend failures | Medium | Graceful degradation, clear errors |
| Database lock contention | Medium | Background processing, small batches |

## References

- [NLNet Master Issue](https://git.pleroma.social/pleroma/pleroma-meta/-/issues/71)
- [Pleroma Upload Documentation](https://docs.pleroma.social/backend/configuration/cheatsheet/#pleroma-upload)
- [ActivityPub Media Handling](https://www.w3.org/TR/activitypub/#obj-attachment)