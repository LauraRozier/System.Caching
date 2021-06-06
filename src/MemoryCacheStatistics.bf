// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Diagnostics;
using System.Threading;

namespace System.Caching
{
	sealed class MemoryCacheStatistics : IDisposable
	{
		private const int MEMORYSTATUS_INTERVAL_5_SECONDS = 5000;
		private const int MEMORYSTATUS_INTERVAL_30_SECONDS = 30000;
		private int _configCacheMemoryLimitMegabytes;
		private int _configPhysicalMemoryLimitPercentage;
		private int _configPollingInterval;
		private int _inCacheManagerThread;
		private int _disposed;
		private int64 _lastTrimCount;
		private int64 _lastTrimDurationTicks;
		private int _lastTrimPercent;
		private DateTime _lastTrimTime;
		private int _pollingInterval;
		private PeriodicCallback _timer;
		private Monitor _timerLock = new .();
		private int64 _totalCountBeforeTrim;
		private CacheMemoryMonitor _cacheMemoryMonitor;
		private MemoryCache _memoryCache;
		private PhysicalMemoryMonitor _physicalMemoryMonitor;

		private this() { }

		private void AdjustTimer()
		{
			using (_timerLock.Enter())
			{
				if (_timer != null)
				{
					if (_physicalMemoryMonitor.IsAboveHighPressure() || _cacheMemoryMonitor.IsAboveHighPressure())
					{
						if (_pollingInterval > 5000)
						{
							_pollingInterval = 5000;
							_timer.UpdateInterval(_pollingInterval);
						}
					}
					else if (_cacheMemoryMonitor.PressureLast > _cacheMemoryMonitor.PressureLow / 2 || _physicalMemoryMonitor.PressureLast > _physicalMemoryMonitor.PressureLow / 2)
					{
						int interval = Math.Min(_configPollingInterval, 30000);

						if (_pollingInterval != interval)
						{
							_pollingInterval = interval;
							_timer.UpdateInterval(_pollingInterval);
						}
					}
					else if (_pollingInterval != _configPollingInterval)
					{
						_pollingInterval = _configPollingInterval;
						_timer.UpdateInterval(_pollingInterval);
					}
				}
			}
		}

		private void CacheManagerTimerCallback(PeriodicCallback state) =>
			CacheManagerThread(0);

		public int64 GetLastSize() =>
			(int64)_cacheMemoryMonitor.PressureLast;

		private int GetPercentToTrim() =>
			Math.Max(_physicalMemoryMonitor.GetPercentToTrim(_lastTrimTime, _lastTrimPercent), _cacheMemoryMonitor.GetPercentToTrim(_lastTrimTime, _lastTrimPercent));

		private void SetTrimStats(int64 trimDurationTicks, int64 totalCountBeforeTrim, int64 trimCount)
		{
			_lastTrimDurationTicks = trimDurationTicks;
			_lastTrimTime = DateTime.UtcNow;
			_totalCountBeforeTrim = totalCountBeforeTrim;
			_lastTrimCount = trimCount;
			_lastTrimPercent = (int)(_lastTrimCount * 100L / _totalCountBeforeTrim);
		}

		private void Update()
		{
			_physicalMemoryMonitor.Update();
			_cacheMemoryMonitor.Update();
		}

		public int64 CacheMemoryLimit
		{
			get { return _cacheMemoryMonitor.MemoryLimit; }
		}

		public int64 PhysicalMemoryLimit
		{
			get { return _physicalMemoryMonitor.MemoryLimit; }
		}

		public TimeSpan PollingInterval
		{
			get { return TimeSpan(_configPollingInterval * TimeSpan.TicksPerMillisecond); }
		}

		public this(MemoryCache memoryCache)
		{
			_memoryCache = memoryCache;
			_lastTrimTime = DateTime.MinValue;
			_configPollingInterval = (int)TimeSpan(0, 0, 20).TotalMilliseconds;
			_configCacheMemoryLimitMegabytes = 0;
			_configPhysicalMemoryLimitPercentage = 0;
			_pollingInterval = _configPollingInterval;
			_physicalMemoryMonitor = new .(_configPhysicalMemoryLimitPercentage);
			_cacheMemoryMonitor = new .(_memoryCache, _configCacheMemoryLimitMegabytes);
			_timer = new .(new => CacheManagerTimerCallback, _configPollingInterval);
		}

		public int64 CacheManagerThread(int minPercent)
		{
			if (Interlocked.Exchange(ref _inCacheManagerThread, 1) != 0)
				return 0L;

			int64 result = 0L;

			if (_disposed != 1)
			{
				Update();
				AdjustTimer();
				int trimAmount = Math.Max(minPercent, GetPercentToTrim());
				int64 count = _memoryCache.GetCount();
				Stopwatch stopwatch = Stopwatch.StartNew();
				int64 trimmed = _memoryCache.Trim(trimAmount);
				stopwatch.Stop();

				if (trimAmount > 0 && trimmed > 0L)
					SetTrimStats(stopwatch.Elapsed.Ticks, count, trimmed);

				result = trimmed;
				delete stopwatch;
			}

			Interlocked.Exchange(ref _inCacheManagerThread, 0);
			return result;
		}

		public void Dispose()
		{
			if (Interlocked.Exchange(ref _disposed, 1) == 0)
			{
				using (_timerLock.Enter())
				{
					PeriodicCallback timer = _timer;

					if (timer != null && Interlocked.CompareExchange(ref _timer, null, timer) == timer)
					{
						timer.Dispose();
						DeleteAndNullify!(timer);
					}
				}

				while (_inCacheManagerThread != 0)
					Thread.Sleep(100);

				if (_cacheMemoryMonitor != null)
				{
					_cacheMemoryMonitor.Dispose();
					DeleteAndNullify!(_cacheMemoryMonitor);
				}
				
				DeleteAndNullify!(_physicalMemoryMonitor);
				DeleteAndNullify!(_timerLock);
			}
		}
	}
}
