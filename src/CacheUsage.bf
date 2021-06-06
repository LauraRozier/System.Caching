// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Threading;

namespace System.Caching
{
	class CacheUsage
	{
		public static readonly TimeSpan NEWADD_INTERVAL = TimeSpan(0, 0, 10);
		public static readonly TimeSpan CORRELATED_REQUEST_TIMEOUT = TimeSpan(0, 0, 1);
		public static readonly TimeSpan MIN_LIFETIME_FOR_USAGE = NEWADD_INTERVAL;

		private const uint8 NUMBUCKETS = 1;
		private const int MAX_REMOVE = 1024;

		private readonly MemoryCacheStore _cacheStore;
		private readonly UsageBucket[] _buckets ~ DeleteContainerAndItems!(_);
		private int _inFlush;

		public this(MemoryCacheStore cacheStore)
		{
			_cacheStore = cacheStore;
			_buckets = new .[1];
			uint8 b = 0;

			while ((int)b < _buckets.Count)
			{
				_buckets[(int)b] = new .(this, b);
				b += 1;
			}
		}

		public MemoryCacheStore MemoryCacheStore
		{
			get { return _cacheStore; }
		}

		public void Add(MemoryCacheEntry cacheEntry)
		{
			uint8 usageBucket = cacheEntry.UsageBucket;
			_buckets[(int)usageBucket].AddCacheEntry(cacheEntry);
		}

		public void Remove(MemoryCacheEntry cacheEntry)
		{
			uint8 usageBucket = cacheEntry.UsageBucket;

			if (usageBucket != 255)
				_buckets[(int)usageBucket].RemoveCacheEntry(cacheEntry);
		}

		public void Update(MemoryCacheEntry cacheEntry)
		{
			uint8 usageBucket = cacheEntry.UsageBucket;

			if (usageBucket != 255)
				_buckets[(int)usageBucket].UpdateCacheEntry(cacheEntry);
		}

		public int FlushUnderUsedItems(int toFlush)
		{
			int totalFlushed = 0;

			if (Interlocked.Exchange(ref _inFlush, 1) == 0)
			{
				for (let bucket in _buckets)
				{
					int flushedCount = bucket.FlushUnderUsedItems(toFlush - totalFlushed, false);
					totalFlushed += flushedCount;

					if (totalFlushed >= toFlush)
						break;
				}

				if (totalFlushed < toFlush)
					for (let bucket in _buckets)
					{
						int flushedCount = bucket.FlushUnderUsedItems(toFlush - totalFlushed, true);
						totalFlushed += flushedCount;

						if (totalFlushed >= toFlush)
							break;
					}

				Interlocked.Exchange(ref _inFlush, 0);
			}

			return totalFlushed;
		}
	}
}
