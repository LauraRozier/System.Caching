// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public enum CacheEntryRemovedReason
	{
		Removed = 0,           // Explicitly removed via API call
		Expired,
		Evicted,               // Evicted to free up space
		ChangeMonitorChanged,  // An associated programmatic dependency triggered eviction
		CacheSpecificEviction, // Catch-all for custom providers
		Disposing
	}

	public enum CacheItemPriority
	{
		Default = 0,
		NotRemovable
	}

	public enum DefaultCacheCapabilities
	{
		None = 0x0,
		InMemoryProvider = 0x1,
		OutOfProcessProvider = 0x2,
		CacheEntryChangeMonitors = 0x4,
		AbsoluteExpirations = 0x8,
		SlidingExpirations = 0x10,
		CacheEntryUpdateCallback = 0x20,
		CacheEntryRemovedCallback = 0x40,
		CacheRegions = 0x80
	}

	public enum EntryState : uint8
	{
		NotInCache = 0,
		AddingToCache = 1,
		AddedToCache = 2,
		RemovingFromCache = 4,
		RemovedFromCache = 8,
		Closed = 16
	}
}
