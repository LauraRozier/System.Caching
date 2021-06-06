// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;
using System.Threading;

namespace System.Caching
{
	sealed class MemoryCacheStore : IDisposable
	{
		private const int INSERT_BLOCK_WAIT = 10000;
		private const int MAX_COUNT = Int32.MaxValue / 2;

		private Dictionary<String, MemoryCacheEntry> _entries = new .();
		private Monitor _entriesLock = new .();
		private CacheExpires _expires = new .(this);
		private CacheUsage _usage = new .(this);
		private uint8 _disposed;
		private WaitEvent _insertBlock = new .(true);
		private volatile bool _useInsertBlock;
		private MemoryCache _cache;

		public this(MemoryCache cache)
		{
			_cache = cache;
			_expires.EnableExpirationTimer(true);
		}

		private void AddToCache(MemoryCacheEntry entry)
		{
			// add outside of lock
			if (entry == null)
				return;
			
			MemoryCacheEntry newEntry = entry;

			if (newEntry.HasExpiration())
				_expires.Add(newEntry);

			if (newEntry.HasUsage() && (!newEntry.HasExpiration() || newEntry.UtcAbsExp - DateTime.UtcNow >= CacheUsage.MIN_LIFETIME_FOR_USAGE))
				_usage.Add(newEntry);

			// One last sanity check to be sure we didn't fall victim to an Add ----
			if (!newEntry.CompareExchangeState(.AddedToCache, .AddingToCache))
			{
				if (newEntry.InExpires())
					_expires.Remove(newEntry);

				if (newEntry.InUsage())
					_usage.Remove(newEntry);
			}

			newEntry.CallNotifyOnChanged();
		}

		private void RemoveFromCache(MemoryCacheEntry entry, CacheEntryRemovedReason reason, bool delayRelease = false)
		{
			// release outside of lock
			if (entry != null)
			{
				if (entry.InExpires())
					_expires.Remove(entry);

				if (entry.InUsage())
					_usage.Remove(entry);

				Runtime.Assert(entry.State == .RemovingFromCache);
				entry.State = .RemovedFromCache;

				if (!delayRelease)
					entry.Release(_cache, reason);
			}
		}

		/// 'updatePerfCounters' defaults to true since this method is called by all Get() operations to update both the performance counters and the sliding expiration. Callers that perform
		/// nested sliding expiration updates (like a MemoryCacheEntry touching its update sentinel) can pass false to prevent these from unintentionally showing up in the perf counters.
		public void UpdateExpAndUsage(MemoryCacheEntry entry)
		{
			if (entry != null)
			{
				if (entry.InUsage() || entry.SlidingExp > TimeSpan.Zero)
				{
					DateTime utcNow = DateTime.UtcNow;
					entry.UpdateSlidingExp(utcNow, _expires);
					entry.UpdateUsage(utcNow, _usage);
				}

				// If this entry has an update sentinel, the sliding expiration is actually associated  with that sentinel, not with this entry. We need to update the sentinel's sliding expiration to
				// keep the sentinel from expiring, which in turn would force a removal of this entry from the cache.
				entry.UpdateSlidingExpForUpdateSentinel();
			}
		}

		private void WaitInsertBlock() =>
			_insertBlock.WaitFor(INSERT_BLOCK_WAIT);

		public CacheUsage Usage
		{
			get { return _usage; }
		}

		public MemoryCacheEntry AddOrGetExisting(String key, MemoryCacheEntry entry, bool deleteValueIfExists)
		{
			var entry;

			if (_useInsertBlock && entry.HasUsage())
				WaitInsertBlock();

			MemoryCacheEntry existingEntry = null;
			MemoryCacheEntry toBeReleasedEntry = null;
			bool added = false;

			using (_entriesLock.Enter())
			{
				if (_disposed == 0)
				{
					if (_entries.ContainsKey(key))
					{
						existingEntry = _entries[key];

						// has it expired?
						if (existingEntry != null && existingEntry.UtcAbsExp <= DateTime.UtcNow)
						{
							toBeReleasedEntry = existingEntry;
							toBeReleasedEntry.State = .RemovingFromCache;
							existingEntry = null;
						}
					}

					// can we add entry to the cache?
					if (existingEntry == null)
					{
						entry.State = .AddingToCache;
						added = true;
						_entries[key] = entry;
					}
					else
					{
						if (deleteValueIfExists)
							delete entry.Value;

						DeleteAndNullify!(entry);
					}
				}

				RemoveFromCache(toBeReleasedEntry, .Expired, true);
			}

			if (added) // add outside of lock
				AddToCache(entry);

			// update outside of lock
			UpdateExpAndUsage(existingEntry);

			// Call Release after the new entry has been completely added so that the CacheItemRemovedCallback can take
			// a dependency on the newly inserted item.
			if (toBeReleasedEntry != null)
			{
				toBeReleasedEntry.Release(_cache, .Expired);
				DeleteAndNullify!(toBeReleasedEntry);
			}

			return existingEntry;
		}

		public void BlockInsert()
		{
			_insertBlock.Reset();
			_useInsertBlock = true;
		}

		public void CopyTo(ref Dictionary<String, ExistingEntry> h)
		{
			using (_entriesLock.Enter())
				if (_disposed == 0)
					for (let e in _entries)
						if (e.value.UtcAbsExp > DateTime.UtcNow)
							h[e.key] = .(e.value.State, e.value.Value);
		}

		public int Count
		{
			get { return _entries.Count; }
		}

		public void Dispose()
		{
			if (Interlocked.Exchange(ref _disposed, 1) == 0)
			{
				// disable CacheExpires timer
				_expires.EnableExpirationTimer(false);
				// build array list of entries
				List<MemoryCacheEntry> entries = scope .(_entries.Count);

				using (_entriesLock.Enter())
				{
					for (let e in _entries)
					{
						MemoryCacheEntry entry = e.value;
						entries.Add(entry);
					}

					for (let entry in entries)
					{
						entry.State = .RemovingFromCache;
						_entries.Remove(entry.Key);
					}
				}

				// release entries outside of lock
				for (var entry in entries)
				{
					RemoveFromCache(entry, .Disposing);
					Object val = entry.Value;

					if (val != null)
						DeleteAndNullify!(val);

					DeleteAndNullify!(entry);
				}

				DeleteAndNullify!(_entries);
				DeleteAndNullify!(_entriesLock);
				DeleteAndNullify!(_expires);
				DeleteAndNullify!(_usage);

				// MemoryCacheStatistics has been disposed, and therefore nobody should be using _insertBlock except for
				// potential threads in WaitInsertBlock (which won't care if we call Close).
				Runtime.Assert(_useInsertBlock == false);
				DeleteAndNullify!(_insertBlock);
			}
		}

		public MemoryCacheEntry Get(String key)
		{
			MemoryCacheEntry entry = _entries[key];

			// has it expired?
			if (entry != null && entry.UtcAbsExp <= DateTime.UtcNow)
			{
				Remove(key, entry, .Expired);
				DeleteAndNullify!(entry);
			}

			// update outside of lock
			UpdateExpAndUsage(entry);
			return entry;
		}

		public MemoryCacheEntry Remove(String key, MemoryCacheEntry entryToRemove, CacheEntryRemovedReason reason)
		{
			MemoryCacheEntry entry = null;

			using (_entriesLock.Enter())
				if (_disposed == 0)
					if (_entries.ContainsKey(key))
					{
						// get current entry
						entry = _entries[key];

						// remove if it matches the entry to be removed (but always remove if entryToRemove is null)
						if (entryToRemove == null || entry == entryToRemove)
						{
							if (entry != null)
							{
								entry.State = .RemovingFromCache;
								_entries.Remove(key);
							}
						}
						else
						{
							entry = null;
						}
					}

			// release outside of lock
			RemoveFromCache(entry, reason);
			return entry;
		}

		public void Set(String key, MemoryCacheEntry entry)
		{
			if (_useInsertBlock && entry.HasUsage())
				WaitInsertBlock();

			MemoryCacheEntry existingEntry = null;
			bool added = false;

			using (_entriesLock.Enter())
				if (_disposed == 0)
				{
					existingEntry = _entries[key];

					if (existingEntry != null)
						existingEntry.State = .RemovingFromCache;

					entry.State = .AddingToCache;
					added = true;
					_entries[key] = entry;
				}

			CacheEntryRemovedReason reason = .Removed;

			if (existingEntry != null)
			{
				if (existingEntry.UtcAbsExp <= DateTime.UtcNow)
					reason = .Expired;

				RemoveFromCache(existingEntry, reason, true);
			}

			if (added)
				AddToCache(entry);

			// Call Release after the new entry has been completely added so that the CacheItemRemovedCallback can take
			// a dependency on the newly inserted item.
			if (existingEntry != null)
			{
				existingEntry.Release(_cache, reason);
				DeleteAndNullify!(existingEntry);
			}
		}

		public int64 TrimInternal(int percent)
		{
			Runtime.Assert(percent <= 100);

			int count = Count;
			int toTrim = 0;

			// do we need to drop a percentage of entries?
			if (percent > 0)
			{
				toTrim = (int)Math.Ceiling(((int64)count * (int64)percent) / 100D);
				// would this leave us above MAX_COUNT?
				int minTrim = count - MAX_COUNT;

				if (toTrim < minTrim)
					toTrim = minTrim;
			}

			// do we need to trim?
			if (toTrim <= 0 || _disposed == 1)
				return 0;

			int trimmed = 0; // total number of entries trimmed
			int trimmedOrExpired = 0;

			trimmedOrExpired = _expires.FlushExpiredItems(true);

			if (trimmedOrExpired < toTrim)
			{
				trimmed = _usage.FlushUnderUsedItems(toTrim - trimmedOrExpired);
				trimmedOrExpired += trimmed;
			}

			return trimmedOrExpired;
		}

		public void UnblockInsert()
		{
			_useInsertBlock = false;
			_insertBlock.Set();
		}
	}
}
