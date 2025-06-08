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

## Implementation Design

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

**Note:** Will fail if media is currently used in posts or profile.

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

2. **`Pleroma.Upload.UserMedia`**
   - Core business logic
   - Query building and optimization
   - Validation of ownership
   - Integration with storage backends

3. **`Pleroma.Upload.MediaStats`**
   - Calculate usage statistics
   - Cache management for performance
   - Aggregation queries

4. **`Pleroma.Workers.MediaDeletionWorker`**
   - Background processing for bulk deletions
   - Safe cleanup with rollback support
   - Progress tracking

#### Database Optimizations

1. **New Indexes**
   ```sql
   CREATE INDEX objects_actor_index ON objects ((data->>'actor'));
   CREATE INDEX objects_type_index ON objects ((data->>'type'));
   CREATE INDEX objects_uploaded_at_index ON objects ((data->>'published'));
   ```

2. **Media View** (Optional)
   ```sql
   CREATE VIEW user_media AS
   SELECT 
     id,
     data->>'actor' as actor,
     data->>'url' as url,
     data->>'mediaType' as media_type,
     data->>'name' as description,
     (data->>'size')::bigint as size,
     data->>'published' as uploaded_at,
     data
   FROM objects
   WHERE data->>'type' = 'Document';
   ```

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

### Phase 1: Core Functionality (3 days)
- [ ] Create database indexes
- [ ] Implement UserMedia module with basic queries
- [ ] Create MediaController with list and delete endpoints
- [ ] Add authentication and authorization
- [ ] Basic tests

### Phase 2: Enhanced Features (3 days)
- [ ] Add filtering and search capabilities
- [ ] Implement bulk operations
- [ ] Create MediaStats module
- [ ] Add media usage statistics endpoint
- [ ] Implement caching layer

### Phase 3: Integration & Polish (2 days)
- [ ] Hook into existing cleanup workers
- [ ] Add admin controls and overrides
- [ ] Implement audit logging
- [ ] Add Prometheus metrics
- [ ] Performance optimization

### Phase 4: Testing & Documentation (2 days)
- [ ] Comprehensive test suite
- [ ] API documentation
- [ ] Admin configuration guide
- [ ] User documentation for PleromaFE
- [ ] Migration guide for existing instances

## Testing Strategy

### Unit Tests
- UserMedia query functions
- MediaStats calculations
- Authorization logic
- Cache invalidation

### Integration Tests
- Full API flow with different storage backends
- Bulk operations with large datasets
- Error handling and edge cases
- Rate limiting behavior

### Performance Tests
- Query performance with 10k+ uploads
- Bulk deletion performance
- Cache effectiveness
- Database index usage

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