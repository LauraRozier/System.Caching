using System;
using System.Caching;
using System.Caching.Timer;
using System.Diagnostics;
using System.Threading;

namespace test_app
{
	class Program
	{
        private const int CCacheTimeMilliseconds = 1000;
		
		private static int _iterations = 1;
		private static int _cahedItem = 0;
		private static int _prevCahedItem = 0;
		private static bool _needsUpdate = false;
		private static readonly Stopwatch _sw = new Stopwatch() ~ delete _;
        private static readonly MemoryCache _memCache = MemoryCache.Default ~ _.Dispose();
		private static readonly CacheItemPolicy _policy = new .() {
			RemovedCallback = new => CacheItemPolicy_RemovedCallback
		} ~ delete _;
		private static Object _object = new Object() ~ delete _;
		private static String _tmpStr = new String() ~ delete _;

		static void Main()
		{
			_sw.Start();
			using (PeriodicCallback timer = new PeriodicCallback(new => DoStuff, TimeSpan(0, 0, 2))) {
				while (true) {
					Thread.Sleep(100);

					/*
					if (_needsUpdate) {
						timer.UpdateInterval(TimeSpan(0, 0, 3));
						_needsUpdate = false;
					}
					*/
				}
			}
		}

		private static void DoStuff(PeriodicCallback caller)
		{
			/*
			_sw.Stop();
			Console.Out.WriteLine(scope $"This is DoStuff iteration: {_iterations}\nElapsed ms: {_sw.ElapsedMilliseconds}");
			*/

			if (_iterations % 5 == 0) {
				_policy.AbsoluteExpiration = DateTimeOffset.Now.AddMilliseconds(CCacheTimeMilliseconds);
	            // Only add if it is not there already (swallow others)
				_tmpStr.Clear();
				_cahedItem.ToString(_tmpStr);
	            _memCache.AddOrGetExisting("Timer Update", _tmpStr, _policy);
				_cahedItem++;
			}
			
			/*
			if (_iterations == 5)
				_needsUpdate = true;
			
			_sw.Restart();
			*/
			_iterations++;
		}

		private static void CacheItemPolicy_RemovedCallback(CacheEntryRemovedArguments args)
		{
			int itemNo = TrySilent!(Int.Parse((String)args.CacheItem.Value));
			Console.Out.WriteLine(scope $"\nItem is removed from the cache\nReason: {args.RemovedReason}\nItem# {itemNo}\n");

			if (itemNo - _prevCahedItem > 1)
				Runtime.FatalError("We missed a cache item");

			_prevCahedItem = itemNo;
		}
	}
}
