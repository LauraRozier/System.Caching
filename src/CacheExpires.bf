// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Threading;

namespace System.Caching
{
	sealed class CacheExpires
	{
		private const int NUMBUCKETS = 30;

		public static readonly TimeSpan MIN_UPDATE_DELTA = TimeSpan(0, 0, 1);
		public static readonly TimeSpan MIN_FLUSH_INTERVAL = TimeSpan(0, 0, 1);
		public static readonly TimeSpan _tsPerBucket = TimeSpan(0, 0, 20);
		private static readonly TimeSpan s_tsPerCycle = TimeSpan(30L * _tsPerBucket.Ticks);

		private readonly MemoryCacheStore _cacheStore;
		private readonly ExpiresBucket[] _buckets = new .[30] ~ DeleteContainerAndItems!(_);
		private PeriodicCallback _timer = null ~ if (_ != null) DeleteAndNullify!(_);
		private DateTime _utcLastFlush;
		private int _inFlush;

		public this(MemoryCacheStore cacheStore)
		{
			DateTime utcNow = DateTime.UtcNow;
			_cacheStore = cacheStore;
			uint8 b = 0;

			while ((int)b < _buckets.Count)
			{
				_buckets[(int)b] = new .(this, b, utcNow);
				b += 1;
			}
		}

		private int UtcCalcExpiresBucket(DateTime utcDate) =>
			(int)(((utcDate.Ticks % s_tsPerCycle.Ticks) / _tsPerBucket.Ticks + 1L) % 30L);

		private int FlushExpiredItems(bool checkDelta, bool useInsertBlock)
		{
			int flushedCount = 0;

			if (Interlocked.Exchange(ref _inFlush, 1) == 0)
			{
				if (_timer == null)
					return 0;

				DateTime utcNow = DateTime.UtcNow;

				if (!checkDelta || (utcNow - _utcLastFlush) >= MIN_FLUSH_INTERVAL || utcNow < _utcLastFlush)
				{
					_utcLastFlush = utcNow;

					for (let expiresBucket in _buckets)
						flushedCount += expiresBucket.FlushExpiredItems(utcNow, useInsertBlock);
				}

				Interlocked.Exchange(ref _inFlush, 0);
			}

			return flushedCount;
		}

		public int FlushExpiredItems(bool useInsertBlock) =>
			FlushExpiredItems(true, useInsertBlock);

		private void TimerCallback(PeriodicCallback state) =>
			FlushExpiredItems(false, false);

		public void EnableExpirationTimer(bool enable)
		{
			if (enable)
			{
				if (_timer == null)
				{
					DateTime utcNow = DateTime.UtcNow;
					TimeSpan timeSpan = _tsPerBucket - TimeSpan(utcNow.Ticks % _tsPerBucket.Ticks);
					_timer = new .(new => TimerCallback, timeSpan.Ticks / 10000L);
					return;
				}
			}
			else
			{
				PeriodicCallback timer = _timer;

				if (timer != null && Interlocked.CompareExchange(ref _timer, null, timer) == timer)
				{
					timer.Dispose();

					while (_inFlush != 0)
						Thread.Sleep(100);
				}
			}
		}

		public MemoryCacheStore MemoryCacheStore
		{
			get { return _cacheStore; }
		}

		public void Add(MemoryCacheEntry cacheEntry)
		{
			DateTime utcNow = DateTime.UtcNow;

			if (utcNow > cacheEntry.UtcAbsExp)
				cacheEntry.UtcAbsExp = utcNow;

			_buckets[UtcCalcExpiresBucket(cacheEntry.UtcAbsExp)].AddCacheEntry(cacheEntry);
		}

		public void Remove(MemoryCacheEntry cacheEntry)
		{
			uint8 expiresBucket = cacheEntry.ExpiresBucket;

			if (expiresBucket != 255)
				_buckets[(int)expiresBucket].RemoveCacheEntry(cacheEntry);
		}

		public void UtcUpdate(MemoryCacheEntry cacheEntry, DateTime utcNewExpires)
		{
			int expiresBucket = (int)cacheEntry.ExpiresBucket;
			int bucketIdx = UtcCalcExpiresBucket(utcNewExpires);

			if (expiresBucket != bucketIdx)
			{
				if (expiresBucket != 255)
				{
					_buckets[expiresBucket].RemoveCacheEntry(cacheEntry);
					cacheEntry.UtcAbsExp = utcNewExpires;
					_buckets[bucketIdx].AddCacheEntry(cacheEntry);
					return;
				}
			}
			else if (expiresBucket != 255)
			{
				_buckets[expiresBucket].UtcUpdateCacheEntry(cacheEntry, utcNewExpires);
			}
		}
	}
}
