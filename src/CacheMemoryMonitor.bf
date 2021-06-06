// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Caching.Interface;
using System.Collections;
using System.Threading;

namespace System.Caching
{

	sealed class CacheMemoryMonitor : MemoryMonitor, IDisposable
	{
		private const int64 PRIVATE_BYTES_LIMIT_2GB = 800 * MEGABYTE;
		private const int64 PRIVATE_BYTES_LIMIT_3GB = 1800 * MEGABYTE;
		private const int64 PRIVATE_BYTES_LIMIT_64BIT = 1L * TERABYTE;
		private const int SAMPLE_COUNT = 2;

		private static IMemoryCacheManager s_memoryCacheManager;
		private static int64 s_autoPrivateBytesLimit = -1;
		private static int64 s_effectiveProcessMemoryLimit = -1;

		private MemoryCache _memoryCache;
		private int64[] _cacheSizeSamples;
		private DateTime[] _cacheSizeSampleTimes;
		private int _idx;
		private List<MemoryCacheStore> _sizedRefMultiple;
		private int64 _memoryLimit;

		public int64 MemoryLimit
		{
			get { return _memoryLimit; }
		}

		private this() { } // hide default ctor

		public this(MemoryCache memoryCache, int cacheMemoryLimitMegabytes)
		{
			_memoryCache = memoryCache;
			_cacheSizeSamples = new .[SAMPLE_COUNT];
			_cacheSizeSampleTimes = new .[SAMPLE_COUNT];

			if (memoryCache.UseMemoryCacheManager)
				InitMemoryCacheManager(); // This magic thing connects us to ObjectCacheHost magically. :/

			InitDisposableMembers(cacheMemoryLimitMegabytes);
		}

		private void InitDisposableMembers(int cacheMemoryLimitMegabytes)
		{
			bool dispose = true;
			let temp = _memoryCache.AllSRefTargets;
			_sizedRefMultiple = new .(temp.GetEnumerator());
			delete temp;
			SetLimit(cacheMemoryLimitMegabytes);
			InitHistory();
			dispose = false;

			if (dispose)
				Dispose();
		}

		/// Auto-generate the private bytes limit:
		/// - On 64bit, the auto value is MIN(60% physical_ram, 1 TB)
		/// - On x86, for 2GB, the auto value is MIN(60% physical_ram, 800 MB)
		/// - On x86, for 3GB, the auto value is MIN(60% physical_ram, 1800 MB)
		///
		/// - If it's not a hosted environment (e.g. console app), the 60% in the above formulas will become 100% because in un-hosted environment we don't launch
		///   other processes such as compiler, etc.
		private static int64 AutoPrivateBytesLimit
		{
			get
			{
				int64 memoryLimit = s_autoPrivateBytesLimit;

				if (memoryLimit == -1)
				{
#if BF_64_BIT
					bool is64bit = true;
#else
					bool is64bit = false;
#endif
					int64 totalPhysical = TotalPhysical;
					int64 totalVirtual = TotalVirtual;

					if (totalPhysical != 0)
					{
						int64 recommendedPrivateByteLimit = is64bit
							? PRIVATE_BYTES_LIMIT_64BIT
							: totalVirtual > 2 * GIGABYTE ? PRIVATE_BYTES_LIMIT_3GB : PRIVATE_BYTES_LIMIT_2GB; // Figure out if it's 2GB or 3GB
						// use 60% of physical RAM
						int64 usableMemory = totalPhysical * 3 / 5;
						memoryLimit = Math.Min(usableMemory, recommendedPrivateByteLimit);
					}
					else
					{
						// If GlobalMemoryStatusEx fails, we'll use these as our auto-gen private bytes limit
						memoryLimit = is64bit ? PRIVATE_BYTES_LIMIT_64BIT : PRIVATE_BYTES_LIMIT_2GB;
					}

					Interlocked.Exchange(ref s_autoPrivateBytesLimit, memoryLimit);
				}

				return memoryLimit;
			}
		}

		public void Dispose()
		{
			List<MemoryCacheStore> sref = _sizedRefMultiple;

			if (sref != null && Interlocked.CompareExchange(ref _sizedRefMultiple, null, sref) == sref)
			{
				for (var value in sref)
					value.Dispose();

				DeleteAndNullify!(sref);
			}

			IMemoryCacheManager memoryCacheManager = s_memoryCacheManager;

			if (memoryCacheManager != null)
				memoryCacheManager.ReleaseCache(_memoryCache);

			DeleteAndNullify!(_cacheSizeSamples);
			DeleteAndNullify!(_cacheSizeSampleTimes);
		}

		public static int64 EffectiveProcessMemoryLimit
		{
			get
			{
				int64 memoryLimit = s_effectiveProcessMemoryLimit;

				if (memoryLimit == -1)
				{
					memoryLimit = AutoPrivateBytesLimit;
					Interlocked.Exchange(ref s_effectiveProcessMemoryLimit, memoryLimit);
				}

				return memoryLimit;
			}
		}

		protected override int GetCurrentPressure()
		{
			// Call GetUpdatedTotalCacheSize to update the total cache size, if there has been a recent Gen 2 Collection.
			// This update must happen, otherwise the CacheManager won't know the total cache size.
			List<MemoryCacheStore> sref = _sizedRefMultiple;
			// increment the index (it's either 1 or 0)
			Runtime.Assert(SAMPLE_COUNT == 2);
			_idx = _idx ^ 1;
			// remember the sample time
			_cacheSizeSampleTimes[_idx] = DateTime.UtcNow;
			// remember the sample value
			_cacheSizeSamples[_idx] = sref.Count * typeof(MemoryCacheStore).Size;
			IMemoryCacheManager memoryCacheManager = s_memoryCacheManager;

			if (memoryCacheManager != null)
				memoryCacheManager.UpdateCacheSize(_cacheSizeSamples[_idx], _memoryCache);

			// if there's no memory limit, then there's nothing more to do
			if (_memoryLimit <= 0)
				return 0;

			int64 cacheSize = _cacheSizeSamples[_idx];

			// use _memoryLimit as an upper bound so that pressure is a percentage (between 0 and 100, inclusive).
			if (cacheSize > _memoryLimit)
				cacheSize = _memoryLimit;

			int result = (int)(cacheSize * 100 / _memoryLimit);
			return result;
		}

		public override int GetPercentToTrim(DateTime lastTrimTime, int lastTrimPercent)
		{
			int percent = 0;

			if (IsAboveHighPressure())
			{
				int64 cacheSize = _cacheSizeSamples[_idx];

				if (cacheSize > _memoryLimit)
					percent = Math.Min(100, (int)((cacheSize - _memoryLimit) * 100L / cacheSize));
			}

			return percent;
		}

		public void SetLimit(int cacheMemoryLimitMegabytes)
		{
			int64 cacheMemoryLimit = cacheMemoryLimitMegabytes;
			cacheMemoryLimit = cacheMemoryLimit << MEGABYTE_SHIFT;
			_memoryLimit = 0;

			// never override what the user specifies as the limit; only call AutoPrivateBytesLimit when the user does
			// not specify one.
			if (cacheMemoryLimit == 0 && _memoryLimit == 0)
			{ // Zero means we impose a limit
				_memoryLimit = EffectiveProcessMemoryLimit;
			}
			else if (cacheMemoryLimit != 0 && _memoryLimit != 0)
			{ // Take the min of "cache memory limit" and the host's "process memory limit".
				_memoryLimit = Math.Min(_memoryLimit, cacheMemoryLimit);
			}
			else if (cacheMemoryLimit != 0)
			{ // _memoryLimit is 0, but "cache memory limit" is non-zero, so use it as the limit
				_memoryLimit = cacheMemoryLimit;
			}

			if (_memoryLimit > 0)
			{
				_pressureHigh = 100;
				_pressureLow = 80;
			}
			else
			{
				_pressureHigh = 99;
				_pressureLow = 97;
			}
		}

		private static void InitMemoryCacheManager()
		{
			if (s_memoryCacheManager == null)
			{
				IMemoryCacheManager memoryCacheManager = null;
				IServiceProvider host = ObjectCache.Host;

				if (host != null)
					memoryCacheManager = host.GetService(typeof(IMemoryCacheManager)) as IMemoryCacheManager;

				if (memoryCacheManager != null)
					Interlocked.CompareExchange(ref s_memoryCacheManager, memoryCacheManager, null);
			}
		}
	}
}
