using System;
using System.Caching;
using System.Caching.Timer;
using System.Diagnostics;
using System.Threading;

namespace test_app
{
	class Program
	{
        private const int CCacheTimeMilliseconds = 25000;
		
		private static int _cahedItem = 0;
        private static readonly MemoryCache _memCache = MemoryCache.Default ~ _.Dispose();
		private static readonly CacheItemPolicy _policy = new .() {
			RemovedCallback = new => CacheItemPolicy_RemovedCallback
		} ~ delete _;

		class CallbackData
		{
			public int CahedItem;
			public Stopwatch Stopwatch ~ delete _;

			private this() {} // Hide default ctor

			public this(int aCahedItem, Stopwatch aStopwatch)
			{
				CahedItem = aCahedItem;
				Stopwatch = aStopwatch;
			}
		}

		static void Main()
		{
			using (PeriodicCallback timer = new PeriodicCallback(new => DoStuff, TimeSpan(0, 0, 10)))
			{
				while (true)
					Thread.Sleep(100);
			}
		}

		private static void DoStuff(PeriodicCallback caller)
		{
			_policy.AbsoluteExpiration = DateTimeOffset.Now.AddMilliseconds(CCacheTimeMilliseconds);
			Console.Out.WriteLine(scope $"_cahedItem is now {_cahedItem}");

            // Only add if it is not there already (swallow others)
            ExistingEntry item = _memCache.AddOrGetExisting("Timer Update", new CallbackData(_cahedItem, Stopwatch.StartNew()), _policy, true);

			if (item.State == .RemovingFromCache || item.State == .RemovedFromCache)
				DeleteAndNullify!(item.Value);

			_cahedItem++;
		}

		private static void CacheItemPolicy_RemovedCallback(CacheEntryRemovedArguments args)
		{
			CallbackData cd = (CallbackData)args.CacheItem.Value;
			cd.Stopwatch.Stop();
			Console.Out.WriteLine(scope $"\nItem is removed from the cache\n  Reason: {args.RemovedReason}\n  Item#: {cd.CahedItem}\n  Time spent in cache: {cd.Stopwatch.Elapsed}\n");
			delete args.CacheItem.Value;
			args.CacheItem.Value = null;
		}
	}
}
