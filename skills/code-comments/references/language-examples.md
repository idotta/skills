# Language-Specific Documentation Patterns

Concrete examples for each language you work with.

## TypeScript / JavaScript

### File Header

```typescript
// api/users.ts
//
// User CRUD operations against the backend API.
// All functions return typed responses and throw ApiError on failure.
//
// Authentication: Requires valid JWT in AuthContext. These functions
// read the token automatically—callers don't pass it explicitly.
//
// Rate limiting: Backend limits to 100 req/min per user. The functions
// here don't handle rate limiting; see useRateLimitedQuery for that.
```

### TSDoc for Exported Functions

```typescript
/**
 * Fetches paginated user list with optional filters.
 *
 * @param options.page - 1-indexed page number (default: 1)
 * @param options.limit - Results per page, max 100 (default: 20)
 * @param options.role - Filter by role, omit for all roles
 * @returns Paginated response with users and total count
 *
 * @example
 * // Get first page of admins
 * const admins = await getUsers({ role: 'admin' });
 *
 * @throws {ApiError} 401 if not authenticated
 * @throws {ApiError} 403 if caller lacks user:read permission
 */
export async function getUsers(options: GetUsersOptions): Promise<PaginatedUsers>
```

### React Component Documentation

```tsx
// components/UserAvatar.tsx
//
// Displays user profile picture with fallback to initials.
// Handles loading states, broken image URLs, and missing users gracefully.
//
// Sizes: 'sm' (24px), 'md' (40px), 'lg' (64px), 'xl' (96px)
// Uses Next.js Image for automatic optimization on non-fallback images.

interface UserAvatarProps {
  /** User object, or null for anonymous/loading state */
  user: User | null;
  /** Display size - affects both dimensions and font size */
  size?: 'sm' | 'md' | 'lg' | 'xl';
  /** Show online indicator dot */
  showStatus?: boolean;
  /** Called when avatar is clicked, omit to disable click behavior */
  onClick?: () => void;
}

export function UserAvatar({ user, size = 'md', showStatus, onClick }: UserAvatarProps) {
  // Fallback chain: profile pic → initials → generic icon
  // This handles: new users without pics, broken S3 URLs, deleted accounts
```

### Hook Documentation

```typescript
// hooks/useDebounce.ts
//
// Debounces a value, returning the latest value after the specified delay
// with no intermediate updates. Useful for search inputs, form validation,
// and anything that triggers expensive operations on change.
//
// Unlike lodash debounce, this is reactive—works with React state.

/**
 * @param value - Value to debounce
 * @param delay - Milliseconds to wait after last change (default: 300)
 * @returns The debounced value
 *
 * @example
 * const [search, setSearch] = useState('');
 * const debouncedSearch = useDebounce(search, 500);
 *
 * // API call only fires 500ms after user stops typing
 * useEffect(() => {
 *   if (debouncedSearch) fetchResults(debouncedSearch);
 * }, [debouncedSearch]);
 */
export function useDebounce<T>(value: T, delay = 300): T
```

---

## Python

### Module Docstring

```python
"""
user_sync.py - Bidirectional sync between local DB and external identity provider.

Runs on a schedule (see celery_config.py) and can be triggered manually via
the admin panel. Handles conflicts by preferring the most recently modified
record, except for security-sensitive fields which always come from the IdP.

External dependencies:
- OKTA_API_KEY env var for IdP authentication
- Redis for distributed locking (prevents concurrent syncs)

Usage:
    # Full sync (typically nightly)
    sync_all_users()

    # Single user sync (on-demand)
    sync_user(user_id="abc123")
"""
```

### Function Docstring (Google Style)

```python
def calculate_subscription_price(
    plan: Plan,
    billing_cycle: BillingCycle,
    coupon_code: str | None = None,
) -> PriceBreakdown:
    """
    Calculate final price for a subscription including discounts and taxes.

    Applies coupon if valid, calculates regional tax based on the user's
    billing address, and determines any applicable volume discounts.

    Args:
        plan: The subscription plan to price.
        billing_cycle: Monthly or annual billing. Annual gets 2 months free.
        coupon_code: Optional promotional code. Invalid codes are silently
            ignored (returns full price).

    Returns:
        PriceBreakdown with subtotal, discount, tax, and total fields.
        All amounts in cents (USD).

    Raises:
        PlanNotAvailableError: If the plan is archived or region-restricted.

    Example:
        >>> breakdown = calculate_subscription_price(
        ...     plan=Plan.PRO,
        ...     billing_cycle=BillingCycle.ANNUAL,
        ...     coupon_code="SAVE20"
        ... )
        >>> print(f"Total: ${breakdown.total / 100:.2f}")
        Total: $191.20
    """
```

### Class Docstring

```python
class RateLimiter:
    """
    Token bucket rate limiter with Redis backend for distributed limiting.

    Each key (typically user ID or IP) gets its own bucket. Tokens refill
    continuously at the specified rate. Requests consume tokens; when the
    bucket is empty, requests are rejected until tokens refill.

    Thread-safe and works across multiple server instances via Redis.

    Attributes:
        capacity: Maximum tokens per bucket.
        refill_rate: Tokens added per second.
        redis: Redis client for distributed state.

    Example:
        limiter = RateLimiter(capacity=100, refill_rate=10)

        if limiter.allow(user_id):
            process_request()
        else:
            raise TooManyRequestsError()
    """
```

---

## C++

### File Header

```cpp
/**
 * @file telemetry/MetricBuffer.h
 *
 * Thread-safe buffer for metrics before batch export.
 * Batches are flushed either on size threshold or timer tick.
 *
 * Rationale: buffering reduces network chatter and keeps hot paths fast.
 * The exporter runs on a single background thread.
 */
```

### Class Documentation (Doxygen Style)

```cpp
/**
 * Ring buffer of metric points with bounded memory usage.
 *
 * Overwrites oldest entries when full. This trades accuracy for
 * predictable memory, which is acceptable for high-volume metrics.
 */
class MetricBuffer {
public:
    /** Adds a metric point; never blocks the caller. */
    void Push(MetricPoint point);

    /** Drains up to max_items into out; returns count drained. */
    size_t Drain(size_t max_items, std::vector<MetricPoint> &out);
};
```

### Function Documentation (Doxygen Style)

```cpp
/**
 * Fetch a cached value if present and not expired.
 *
 * Keys are case-sensitive. Expired entries are removed on read to
 * keep the hot path simple and avoid a separate sweeper thread.
 *
 * @param cache Cache instance to query.
 * @param key   Null-terminated key string.
 * @return Pointer to value buffer, or NULL if missing/expired.
 */
const char *cache_get(Cache *cache, const char *key);
```

---

## C#

### File Header

```csharp
// Services/TokenRefresher.cs
//
// Refreshes access tokens before they expire to avoid 401s at runtime.
// Runs on a background timer and exposes a manual refresh entry point.
//
// Note: Uses a jittered delay to avoid thundering herd on app startup.
```

### XML Doc Comments

```csharp
/// <summary>
/// Refreshes the current user's access token if it is near expiry.
/// </summary>
/// <param name="cancellationToken">Cancels the refresh operation.</param>
/// <returns>
/// True if a refresh occurred; false if the current token was still valid.
/// </returns>
/// <remarks>
/// Uses the refresh token stored in the secure store. If the refresh
/// token is missing, the user is signed out by the caller.
/// </remarks>
public Task<bool> TryRefreshAsync(CancellationToken cancellationToken);
```

---